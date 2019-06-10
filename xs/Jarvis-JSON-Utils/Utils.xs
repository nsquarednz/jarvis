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

#define DEBUG_ON 1
#define DEBUG(...) if (DEBUG_ON) { fprintf (stderr, __VA_ARGS__); }

#define MAX_NUMBER_LEN 50

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
            croak ("UTF-8 overflow at offset %d.", *offset);
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
            croak ("Number too long (> %d chars) at offset %d.", MAX_NUMBER_LEN, start);
        }
        strncpy (tmp, &json[start], *offset - start);
        tmp[*offset - start] = '\0';

        double n = strtold (tmp, NULL);
        if (! isfinite (n)) {
            croak ("Number overflow at offset %d.", start);
        }

        if (is_integer) {
            return newSViv ((long) n);

        } else {
            return newSVnv (n);
        }

        /*

    // Convert to a string.  Note that the string may contain CHR(0).
    } else if (lua_isstring (L, -1)) {
        STRLEN str_len;
        const char *str = lua_tolstring (L, -1, &str_len);        

        // Translate the NIL marker string into an UNDEF?
        if (SvPOK (nil_sv)) {
            STRLEN nil_bytes_len;
            unsigned char *bytes = (unsigned char *) SvPV (nil_sv, nil_bytes_len);        

            if ((nil_bytes_len == str_len) && ! strncmp ((const char *) bytes, str, nil_bytes_len)) {
                return &PL_sv_undef;
            }
        }

        return newSVpv (str, str_len);

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
        croak ("Unexpected character '%c' at offset %d.\n", json[*offset], *offset);
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
