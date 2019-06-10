/******************************************************************************
 * Description: Jarvis JSON decoder compatible with RFC-7159.
 *
 * Licence:
 *       This file is part of the Jarvis WebApp/Database gateway utility.
 *
 *       Jarvis is free software: you can redistribute it and/or modify
 *       it under the terms of the GNU General Public License as published by
 *       the Free Software Foundation, either version 3 of the License, or
 *       (at your option) any later version.
 *
 *       Jarvis is distributed in the hope that it will be useful,
 *       but WITHOUT ANY WARRANTY; without even the implied warranty of
 *       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *       GNU General Public License for more details.
 *
 *       You should have received a copy of the GNU General Public License
 *       along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
 *
 *       This software is Copyright 2019 by Jonathan Couper-Smartt.
 ******************************************************************************
 */
 
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

#define DEBUG_ON 0
#define DEBUG(...) if (DEBUG_ON) { fprintf (stderr, __VA_ARGS__); }

#define MAX_NUMBER_LEN 64
#define DEFAULT_STRING_LEN 256

// Converts '0'-'9','a'-'f','A'-'F' into a number 0..15.
#define HEX_VALUE(x) (((x >= '0') && (x <= '9')) ? (x - '0') : (10 + ((x) | 0x20) - 'a'))

/******************************************************************************
 * JSON TO PERL
 *      Converts a text JSON representation into a Perl structure.  
 *      Recurses into sub-elements.  Supports a number of non-standard JSON 
 *      features including:
 *
 *          - Multi-Line Strings
 *          - // Single-Line Comments
 *          - Block Comments
 *
 *      Also extracts references to $vars.
 * 
 * Parameters:
 *      json - Pointer to the JSON raw bytes input
 *      nbytes - Total number of bytes in that JSON
 *      offset - Number of bytes remaining
 *
 * Returns:
 *      sv - Scalar Value from top-of-stack.
 *           Reference count will be 1 (non-mortalised)
 *           Internal Array/Hash elements also have reference count 1 (non-mortalised)
 *****************************************************************************/
SV * json_to_perl_inner (char *json, STRLEN nbytes, STRLEN *offset) {


#define CHARACTER_TABULATION 9
#define LINE_FEED 10
#define LINE_TABULATION 11
#define FORM_FEED 12
#define CARRIAGE_RETURN 13
#define SPACE 32
#define NEXT_LINE 133

#define BACKSLASH 92
#define FRONTSLASH 47
#define DOUBLE_QUOTE 34

#define BACKSPACE 8

    // Assume we're at the start of an object/sub-object.
    // Keep absorbing whitespace until we get to something real.
    //
    while (1) {

        // Nothing left.
        if (*offset >= nbytes) {
            return NULL;
        }

        I32 len = UTF8SKIP (&json[*offset]);
        if (*offset + len > nbytes) {
            croak ("UTF-8 overflow at byte offset %ld.", *offset);
        }

        // We don't support UTF-8 whitespace!
        if (len > 1) {
            break;
        }

        char ch = json[*offset];
        if ((ch == CHARACTER_TABULATION) || (ch == LINE_FEED) || (ch == LINE_TABULATION) || (ch == FORM_FEED) || (ch == CARRIAGE_RETURN) || (ch == SPACE) || (ch == NEXT_LINE)) {
            DEBUG ("Whitespace[%d]: %ld\n", ch, *offset);
            *offset = *offset + 1;
            continue;
        }
        
        // Not whitespace.
        break;
    }

    char ch = json[*offset];
    DEBUG ("Content[%d]: (%ld bytes remain)\n", ch, nbytes - *offset);

    // null is per RFC7159 section 3. Values.
    //
    // We map to the Perl undef.
    //
    if (((nbytes - *offset) >= 4) && (ch == 'n') && ! strncmp (&json[*offset], "null", 4)) {
        return &PL_sv_undef;

    // true/false are per RFC7159 section 3. Values.
    //
    // We map to the standard Perl boolean::true/false.
    //
    } else if ((((nbytes - *offset) >= 4) && (ch == 't') && ! strncmp (&json[*offset], "true", 4)) ||
               (((nbytes - *offset) >= 5) && (ch == 'f') && ! strncmp (&json[*offset], "false", 5))) {

        // Mark the stack and push the $self object pointer onto it.
        dSP;

        ENTER;
        SAVETMPS;

        // No arguments.
        PUSHMARK (SP);
        PUTBACK;

        char *subname = (json[*offset] == 't') ? "boolean::true" : "boolean::false";
        int rcount = call_pv (subname, G_SCALAR);
        SPAGAIN;

        if (rcount != 1) {
            croak ("%s returned bad value count %d", subname, rcount);
        }

        // Take a copy before using it.  POPs is a macro and we only want to execute it ONCE.
        SV *tf_sv = POPs;
        tf_sv = newSVsv (tf_sv);

        PUTBACK;
        FREETMPS;
        LEAVE;

        return  (tf_sv);

    // Numbers are per RFC7159 section 6. Numbers
    //
    // Note that we hand off to the "strtold" C built-in function, which is (hopefully) at least
    // as flexible as the RFC.
    //
    } else if (((ch >= '0') && (ch <= '9')) || (ch == '-')) {

        STRLEN start = *offset;

        int is_integer = 1;

        // Negative marker.
        if (ch == '-') {
            *offset = *offset + 1;
        }
        // int part
        while ((*offset < nbytes) && ((json[*offset] >= '0') && (json[*offset] <= '9'))) {
            *offset = *offset + 1;
        }
        // frac part
        if ((*offset < nbytes) && (json[*offset] == '.')) {
            *offset = *offset + 1;
            while ((*offset < nbytes) && ((json[*offset] >= '0') && (json[*offset] <= '9'))) {
                *offset = *offset + 1;
                is_integer = 0;
            }        
        }
        // exponent
        if ((*offset < nbytes) && ((json[*offset] == 'e') || (json[*offset] == 'E'))) {
            *offset = *offset + 1;
            if ((*offset < nbytes) && ((json[*offset] == '-') || (json[*offset] == '+'))) {
                *offset = *offset + 1;
            }        
            while ((*offset < nbytes) && ((json[*offset] >= '0') && (json[*offset] <= '9'))) {
                *offset = *offset + 1;
            }        
        }

        // Ugh, let's copy this into a temporary buffer just in case.
        char tmp[MAX_NUMBER_LEN + 1];
        if ((*offset - start) > MAX_NUMBER_LEN) {
            croak ("Number too long (> %d chars) at byte offset %ld.", MAX_NUMBER_LEN, start);
        }
        strncpy (tmp, &json[start], *offset - start);
        tmp[*offset - start] = 0;

        double n = strtold (tmp, NULL);
        if (! isfinite (n)) {
            croak ("Number overflow at byte offset %ld.", start);
        }

        if (is_integer) {
            return newSViv ((long) n);

        } else {
            return newSVnv (n);
        }

    // Strings are per RFC7159 section 7. Strings
    //
    // Note that JSON strings must be in double quotes, and we respect that.
    // I did contemplate supporting single quotes as a variant, but it seems pointless.
    //
    // Note: We don't support any magic with UTF-16 surrogates.
    // Each \uXXXX is standalone and generates a UTF-8 sequence of 1-3 bytes.
    //
    } else if (ch == DOUBLE_QUOTE) {

        STRLEN start = *offset;

        // Consume the starting ". 
        *offset = *offset + 1;

        // Assign this as the default string size.  We will re-malloc if and when we outgrow this.
        char *str = (char *) malloc (DEFAULT_STRING_LEN);
        STRLEN max_len = DEFAULT_STRING_LEN;
        STRLEN str_len = 0;
        int is_utf8 = 0;

        while (1) {

            // Nothing left.
            if (*offset >= nbytes) {
                croak ("Unterminated string began at byte offset %ld.", start);
            }

            ch = json[*offset];

            // Terminating ", we're done!
            if (ch == DOUBLE_QUOTE) {
                *offset = *offset + 1;
                break;

            // A backslash.
            } else if (ch == BACKSLASH) {
                *offset = *offset + 1;

                // The sequence to append.
                char seq[6];
                STRLEN len;

                // Double backslash?
                if ((*offset < nbytes) && (json[*offset] == BACKSLASH)) {
                    seq[0] = BACKSLASH;
                    *offset = *offset + (len = 1);

                // Escaped double quote?
                } else if ((*offset < nbytes) && (json[*offset] == DOUBLE_QUOTE)) {
                    seq[0] = DOUBLE_QUOTE;
                    *offset = *offset + (len = 1);

                // Escaped frontslash?
                } else if ((*offset < nbytes) && (json[*offset] == FRONTSLASH)) {
                    seq[0] = FRONTSLASH;
                    *offset = *offset + (len = 1);

                // \b, \f, \n, \r, \t
                } else if ((*offset < nbytes) && (json[*offset] == 'b')) {
                    seq[0] = BACKSPACE;
                    *offset = *offset + (len = 1);

                } else if ((*offset < nbytes) && (json[*offset] == 'f')) {
                    seq[0] = FORM_FEED;
                    *offset = *offset + (len = 1);

                } else if ((*offset < nbytes) && (json[*offset] == 'n')) {
                    seq[0] = LINE_FEED;
                    *offset = *offset + (len = 1);

                } else if ((*offset < nbytes) && (json[*offset] == 'r')) {
                    seq[0] = CARRIAGE_RETURN;
                    *offset = *offset + (len = 1);

                } else if ((*offset < nbytes) && (json[*offset] == 't')) {
                    seq[0] = CHARACTER_TABULATION;
                    *offset = *offset + (len = 1);

                // \x00
                } else if (((*offset + 3) < nbytes) && (json[*offset] == 'x')
                        && isxdigit (json[*offset + 1]) && isxdigit (json[*offset + 2])) {

                    // The hex value.
                    long code_point = 
                        (HEX_VALUE(json[*offset + 1]) << 4)  + (HEX_VALUE(json[*offset + 2]));

                    DEBUG ("Escape '%.4s' code point = 0x%02lx.\n", &json[*offset - 1], code_point)

                    seq[0] = code_point;
                    len = 1;

                    if (code_point <= 0x007F) {
                        seq[0] = code_point & 0x7f;
                        len = 1;

                    } else {
                        seq[0] =  0xc0 | ((code_point >> 6) & 0x1f);
                        seq[1] =  0x80 |  (code_point       & 0x3f);
                        len = 2;
                        is_utf8 = 1;
                    }
                    *offset = *offset + 3;

                // \u0000
                } else if (((*offset + 5) < nbytes) && (json[*offset] == 'u')
                        && isxdigit (json[*offset + 1]) && isxdigit (json[*offset + 2])
                        && isxdigit (json[*offset + 3]) && isxdigit (json[*offset + 4])) {

                    // The UTF-8 code point.
                    long code_point = 
                        (HEX_VALUE(json[*offset + 1]) << 12) + (HEX_VALUE(json[*offset + 2]) << 8) +
                        (HEX_VALUE(json[*offset + 3]) << 4)  + (HEX_VALUE(json[*offset + 4]));

                    DEBUG ("Escape '%.6s' code point = 0x%04lx.\n", &json[*offset - 1], code_point)

                    // We do NOT support UTF-16 surrogates.
                    // If you want code points above 0xFFFF use the non-standard \Uxxxxxx below.
                    //
                    if (code_point <= 0x007F) {
                        seq[0] = code_point & 0x7f;
                        len = 1;

                    } else if (code_point <= 0x07FF) {
                        seq[0] =  0xc0 | ((code_point >> 6) & 0x1f);
                        seq[1] =  0x80 |  (code_point       & 0x3f);
                        len = 2;
                        is_utf8 = 1;

                    } else {
                        seq[0] =  0xe0 | ((code_point >> 12) & 0x0f);
                        seq[1] =  0x80 | ((code_point >> 6)  & 0x3f);
                        seq[2] =  0x80 |  (code_point        & 0x3f);
                        len = 3;
                        is_utf8 = 1;
                    }
                    *offset = *offset + 5;

                // \U000000
                } else if (((*offset + 7) < nbytes) && (json[*offset] == 'U')
                        && isxdigit (json[*offset + 1]) && isxdigit (json[*offset + 2])
                        && isxdigit (json[*offset + 3]) && isxdigit (json[*offset + 4])
                        && isxdigit (json[*offset + 5]) && isxdigit (json[*offset + 6])) {

                    // The UTF-8 code point.
                    long code_point = 
                        (HEX_VALUE(json[*offset + 1]) << 20) + (HEX_VALUE(json[*offset + 2]) << 16) +
                        (HEX_VALUE(json[*offset + 3]) << 12) + (HEX_VALUE(json[*offset + 4]) << 8) +
                        (HEX_VALUE(json[*offset + 5]) << 4)  + (HEX_VALUE(json[*offset + 6]));

                    DEBUG ("Escape '%.8s' code point = 0x%06lx.\n", &json[*offset - 1], code_point)

                    if (code_point <= 0x007F) {
                        seq[0] = code_point & 0x7f;
                        len = 1;

                    } else if (code_point <= 0x07FF) {
                        seq[0] =  0xc0 | ((code_point >> 6) & 0x1f);
                        seq[1] =  0x80 |  (code_point       & 0x3f);
                        len = 2;
                        is_utf8 = 1;

                    } else if (code_point <= 0xFFFF) {
                        seq[0] =  0xe0 | ((code_point >> 12) & 0x0f);
                        seq[1] =  0x80 | ((code_point >> 6)  & 0x3f);
                        seq[2] =  0x80 |  (code_point        & 0x3f);
                        len = 3;
                        is_utf8 = 1;

                    } else {
                        seq[0] =  0xf0 | ((code_point >> 18) & 0x03);
                        seq[1] =  0x80 | ((code_point >> 12) & 0x3f);
                        seq[2] =  0x80 | ((code_point >> 6)  & 0x3f);
                        seq[3] =  0x80 |  (code_point        & 0x3f);
                        len = 4;
                        is_utf8 = 1;
                    }
                    *offset = *offset + 7;

                // Else no good.
                } else {
                    croak ("Unsupported escape sequence at byte offset %ld.", *offset - 1);
                }

                // Do we need to re-alloc our string buffer?
                if ((str_len + len) > max_len) {
                    if ((len > 1) && ! is_utf8) {
                        DEBUG ("String contains UTF-8 characters.\n");
                        is_utf8 = 1;
                    }
                    DEBUG ("Growing string buffer up to %d bytes.\n", DEFAULT_STRING_LEN * 4)
                    char *str2 = (char *) malloc (DEFAULT_STRING_LEN * 4);
                    memcpy (str2, str, str_len);
                    max_len = DEFAULT_STRING_LEN * 4;
                    free (str);
                    str = str2;
                }

                // Copy the byte(s) for this character.
                for (I32 i = 0; i < len; i++) {
                    str[str_len + i] = seq[i];
                }
                str_len = str_len + len;

                // NOTE: Offset was adjusted earlier.

            // Any other characters "as is", including inline UTF-8 (which JSON doesn't officially support).
            } else {
                I32 len = UTF8SKIP (&json[*offset]);
                if (*offset + len > nbytes) {
                    croak ("UTF-8 overflow at byte offset %ld.", *offset);
                }

                // Do we need to re-alloc our string buffer?
                if ((str_len + len) > max_len) {
                    if ((len > 1) && ! is_utf8) {
                        DEBUG ("String contains UTF-8 characters.\n");
                        is_utf8 = 1;
                    }
                    DEBUG ("Growing string buffer up to %d bytes.\n", DEFAULT_STRING_LEN * 4)
                    char *str2 = (char *) malloc (DEFAULT_STRING_LEN * 4);
                    memcpy (str2, str, str_len);
                    max_len = DEFAULT_STRING_LEN * 4;
                    free (str);
                    str = str2;
                }

                // Copy the byte(s) for this character.
                for (I32 i = 0; i < len; i++) {
                    str[str_len + i] = json[*offset + i];
                    if (json[*offset + i] && 0x80) {
                        is_utf8 = 1;
                    }
                }
                str_len = str_len + len;

                // Finall adjust the offset.
                *offset = *offset + len;
            }
        }

        DEBUG ("Returned string is %ld bytes.\n", str_len)
        // A len = 0 tells perl to use strlen to get the length.  That's not what we want.
        if (str_len == 0) {
            str[0] = 0;
        }

        SV *str_sv = newSVpv (str, str_len);
        if (is_utf8) {
            SvUTF8_on (str_sv);
        }

        // NOTE: Do not call free (str).  It is handled by Perl reference counting now.

        return (str_sv);

        /*

    // Handle Tables (and sequences)
    } else if (lua_istable (L, -1)) {

        // Len > 0 indicates a sequence.  Translate into a Perl Array.
        int table_len = luaL_len (L, -1);
        if (table_len > 0) {

            // Initialise a new Array.  AV's reference count is 1.
            AV *av = newAV ();
            SvGETMAGIC ((SV *) av);   

            // Key = nil indicates a fresh iteration.
            lua_pushnil (L);

            // Iterate each element in the table/sequence.  
            // Our table/sequence is now at -2 because the iterator is at the top of the stack.
            //
            while (lua_next (L, -2) != 0) {

                // Now the value is at -1 (top) and the key is at -2.  
                // Recurse to encode the value into a perl SV.
                //
                SV *value_sv = lua_to_perl (L, nil_sv);

                // Pop the lua value off the top.  Keep the key on the stack for the next iteration.
                lua_pop (L, 1);

                // Push the SV onto the array.
                // The SV already has reference count 1 so no need to increment when we push.
                //
                av_push (av, value_sv);
            }                

            // The array already has a reference count of 1 so no increment required.
            return newRV_noinc ((SV *) av);

        // Otherwise use Perl Hash.
        } else {

            // Initialise a new Hash.  HV's reference count is 1.
            HV *hv = newHV ();
            SvGETMAGIC ((SV *) hv);   

            // Key = nil indicates a fresh iteration.
            lua_pushnil (L);

            // Iterate each element in the table/sequence.  
            // Our table/sequence is now at -2 because the iterator is at the top of the stack.
            //
            while (lua_next (L, -2) != 0) {

                // Now the value is at -1 (top) and the key is at -2.  
                // Recurse to encode the value into a perl SV.
                //
                SV *value_sv = lua_to_perl (L, nil_sv);

                // Pop the lua value off the top.  Keep the key on the stack for the next iteration.
                lua_pop (L, 1);

                // The key is now at the top of the stack.  
                // Store the SV in the hash with the associated key value.
                // The SV already has reference count 1 so no need to increment when we store.
                //
                // NOTE: We need to be careful here!
                //
                // We cannot use lua_tostring on a number key in this context because it 
                // modifies the stack and interferes with lua_next.
                //
                if (lua_type (L, -1) == LUA_TSTRING) {
                    STRLEN key_len;
                    const char *key = lua_tolstring (L, -1, &key_len);        

                    hv_store (hv, key, key_len, value_sv, 0);

                // Number key we will handle separately.  
                // We do not support real floating-point number keys.  
                // If you REALLY want floating point keys, specify them as a string with quotes in LUA.
                //
                } else if (lua_type (L, -1) == LUA_TNUMBER) {
                    char key[256];
                    sprintf (key, "%ld", lround (lua_tonumber (L, -1)));

                    hv_store (hv, key, strlen (key), value_sv, 0);

                // Otherwise we have a problem.  Cannot encode this key.
                // The SV has a reference count of 1, need to reduce it to zero so it can be collected.
                //
                } else {
                    SvREFCNT_dec (value_sv);
                }
            }                

            // The hash already has a reference count of 1 so no increment required.
            return newRV_noinc ((SV *) hv);
        }

        */

    // Unsupported syntax.
    // TODO: Print the character (if printable).
    } else {
        croak ("Unexpected character '%c' at byte offset %ld.\n", json[*offset], *offset);
    }
}

MODULE = Jarvis::JSON::Utils PACKAGE = Jarvis::JSON::Utils 

###############################################################################
# DECODE
#       Decodes a JSON string and returns a Perl object.  
#       Will collect args and return them if any are found.
#
# Parameters:
#       json_sv - JSON string to parse.
#
# Returns:
#       object - The Perl object that we parsed from the JSON
#       args - Reference to an array of extracted RHS that begin with "$"
#               [ { name => <part-after-$>, ref => <ref-to-SV> } ]
###############################################################################  
void decode (json_sv)
    SV * json_sv;
PPCODE:

    STRLEN json_len;
    char *json = SvPV (json_sv, json_len);

    STRLEN offset = 0;
    SV *results = json_to_perl_inner (json, json_len, &offset);

    // Should we return an <undef> here?
    if (! results) {
        croak ("No JSON content found.");
    }

    XPUSHs (sv_2mortal (results));
    XSRETURN(1);  
