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

// Some ASCII codes.
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

// Some buffer sizings.
#define MAX_NUMBER_LEN 64
#define DEFAULT_STRING_LEN 256

// Converts '0'-'9','a'-'f','A'-'F' into a number 0..15.
#define HEX_VALUE(x) (((x >= '0') && (x <= '9')) ? (x - '0') : (10 + ((x) | 0x20) - 'a'))

#define FLAG_STRING_ONLY 0x01
#define FLAG_ALLOW_VARS 0x02

/******************************************************************************
 * EAT SPACE
 *      Consumes any whitespace (including comments).
 * 
 * Parameters:
 *      json - Pointer to the JSON raw bytes input
 *      nbytes - Total number of bytes in that JSON
 *      offset - Number of bytes remaining
 *
 * Returns:
 *      void
 *****************************************************************************/
void eat_space (char *json, STRLEN nbytes, STRLEN *offset) {

    // Keep absorbing whitespace until we get to something real.
    while (1) {

        // Nothing left.
        if (*offset >= nbytes) {
            return;
        }

        I32 len = UTF8SKIP (&json[*offset]);
        if (*offset + len > nbytes) {
            croak ("UTF-8 overflow at byte offset %ld.", *offset);
        }

        // We don't support UTF-8 whitespace!
        if (len > 1) {
            break;
        }

        // Single character whitespace.
        char ch = json[*offset];
        if ((ch == CHARACTER_TABULATION) || (ch == LINE_FEED) || (ch == LINE_TABULATION) || 
            (ch == FORM_FEED) || (ch == CARRIAGE_RETURN) || (ch == SPACE) || (ch == NEXT_LINE)) {

            *offset = *offset + 1;
            continue;
        }

        // Comment up to next "\n" end of line (including UTF-8 chars).
        //
        //  # Perl comments.
        //  // C-Style single line comments.
        //  -- SQL-Style single line comments.
        //
        if ((ch == '#') ||
            ((ch == '/') && ((*offset + 1) < nbytes) && (json[*offset + 1] == '/')) ||
            ((ch == '-') && ((*offset + 1) < nbytes) && (json[*offset + 1] == '-'))) {

            DEBUG ("Starting Single-Line Comment[%c] at byte offset %ld\n", ch, *offset);

            // Absorb the second comment-start character if present
            if ((ch = '/') || (ch = '-')) {
                *offset = *offset + 1;
            }

            // Now continue until end of line or end of file.
            while (*offset < nbytes) {
                I32 len = UTF8SKIP (&json[*offset]);
                if (*offset + len > nbytes) {
                    croak ("UTF-8 overflow at byte offset %ld.", *offset);
                }

                // End of line.
                ch = json[*offset];
                if ((len == 1) && (ch == LINE_FEED)) {
                    *offset = *offset + 1;
                    break;
                }

                // Otherwise keep on moving.
                *offset = *offset + len;
            }

            // Go back and look for more whitespace on the next line.
            continue;
        }

        // /* ... Comment Block ... */
        if ((ch == '/') && ((*offset + 1) < nbytes) && (json[*offset + 1] == '*')) {

            STRLEN start = *offset;
            DEBUG ("Starting Multi-Line Comment[/*] at byte offset %ld\n", start);

            // Absorb the second comment-start character.
            *offset = *offset + 1;

            // Now continue until end of block or end of file.
            int in_comment = 1;
            while (*offset < nbytes) {
                I32 len = UTF8SKIP (&json[*offset]);
                if (*offset + len > nbytes) {
                    croak ("UTF-8 overflow at byte offset %ld.", *offset);
                }

                // End of block.
                ch = json[*offset];
                if ((len == 1) && (ch == '*') && ((*offset + 1) < nbytes) && (json[*offset + 1] == '/')) {
                    *offset = *offset + 2;
                    DEBUG ("Content restarts at Multi-Line Comment[*/] at byte offset %ld\n", *offset);
                    in_comment = 0;
                    break;
                }

                // Otherwise keep on moving.
                *offset = *offset + len;
            }

            if (in_comment) {
                croak ("Multi-line comment starting at byte offset %ld was not terminated.", start);
            }

            // Go back and look for more whitespace on the next line.
            continue;            
        }
        
        // Not whitespace.
        break;
    }

    return;
}

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
 *      level - Nested level starting from 0.
 *      json - Pointer to the JSON raw bytes input
 *      nbytes - Total number of bytes in that JSON
 *      offset - Number of bytes remaining
 *      vars_av - Array reference to vars we are collecting (may be NULL if not collecting)      
 *      flags - Special flags that control our handling.
 *
 * Returns:
 *      sv - Scalar Value from top-of-stack.
 *           Reference count will be 1 (non-mortalised)
 *           Internal Array/Hash elements also have reference count 1 (non-mortalised)
 *****************************************************************************/
SV * json_to_perl_inner (int level, char *json, STRLEN nbytes, STRLEN *offset, AV *vars_av, int flags) {

    // Consume leading whitespace.
    eat_space (json, nbytes, offset);

    // End of input, no content found.
    if (*offset >= nbytes) {
        return NULL;
    }

    char ch = json[*offset];
    DEBUG ("I spy something beginning with '%c' at byte offset %ld.\n", ch, *offset);

    // Strings are per RFC7159 section 7. Strings
    //
    // Note that JSON strings must be in double quotes, and we respect that.
    // I did contemplate supporting single quotes as a variant, but it seems pointless.
    //
    // Note: We don't support any magic with UTF-16 surrogates.
    // Each \uXXXX is standalone and generates a UTF-8 sequence of 1-3 bytes.
    //
    if (ch == DOUBLE_QUOTE) {

        // DEBUG ("String capture beginning at byte offset %ld.\n", *offset);
        STRLEN start = *offset;

        // Consume the starting '"'. 
        *offset = *offset + 1;

        // Assign this as the default string size.  We will re-malloc if and when we outgrow this.
        char *str = (char *) malloc (DEFAULT_STRING_LEN);
        STRLEN max_len = DEFAULT_STRING_LEN;
        STRLEN str_len = 0;
        int is_utf8 = 0;
        int is_binary = 0;

        while (1) {

            // Nothing left.
            if (*offset >= nbytes) {
                free (str);
                croak ("Unterminated string beginning at byte offset %ld.", start);
            }

            ch = json[*offset];

            // Terminating '"', we're done!
            if (ch == DOUBLE_QUOTE) {
                *offset = *offset + 1;
                break;
            }

            // The sequence to append.
            char seq[6];
            STRLEN len = 0;

            // A backslash.
            if (ch == BACKSLASH) {
                *offset = *offset + 1;

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

                // NOTE: Use of \x does NOT activate UTF-8!
                // In fact, \x 8-bit characters are NOT permitted in conjunction with UTF-8 8-bit characters.
                //
                // \x00
                } else if (((*offset + 3) < nbytes) && (json[*offset] == 'x')
                        && isxdigit (json[*offset + 1]) && isxdigit (json[*offset + 2])) {

                    // The hex value.
                    long code_point = 
                        (HEX_VALUE(json[*offset + 1]) << 4)  + (HEX_VALUE(json[*offset + 2]));

                    DEBUG ("Escape '%.4s' code point = 0x%02lx.\n", &json[*offset - 1], code_point)

                    seq[0] = code_point;
                    len = 1;

                    if ((code_point > 0x007F) && ! is_binary) {
                        DEBUG (">> \\x 8-bit character turns BINARY ON AT byte offset %ld.\n", *offset)
                        is_binary = 1;
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

                    } else {
                        if (code_point <= 0x07FF) {
                            seq[0] =  0xc0 | ((code_point >> 6) & 0x1f);
                            seq[1] =  0x80 |  (code_point       & 0x3f);
                            len = 2;

                        } else {
                            seq[0] =  0xe0 | ((code_point >> 12) & 0x0f);
                            seq[1] =  0x80 | ((code_point >> 6)  & 0x3f);
                            seq[2] =  0x80 |  (code_point        & 0x3f);
                            len = 3;
                        }
                        if (! is_utf8) {
                            DEBUG (">> \\u %ld-byte code point turns UTF-8 ON AT byte offset %ld.\n", len, *offset)
                            is_utf8 = 1;
                        }
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

                    } else {
                        if (code_point <= 0x07FF) {
                            seq[0] =  0xc0 | ((code_point >> 6) & 0x1f);
                            seq[1] =  0x80 |  (code_point       & 0x3f);
                            len = 2;

                        } else if (code_point <= 0xFFFF) {
                            seq[0] =  0xe0 | ((code_point >> 12) & 0x0f);
                            seq[1] =  0x80 | ((code_point >> 6)  & 0x3f);
                            seq[2] =  0x80 |  (code_point        & 0x3f);
                            len = 3;

                        } else {
                            seq[0] =  0xf0 | ((code_point >> 18) & 0x03);
                            seq[1] =  0x80 | ((code_point >> 12) & 0x3f);
                            seq[2] =  0x80 | ((code_point >> 6)  & 0x3f);
                            seq[3] =  0x80 |  (code_point        & 0x3f);
                            len = 4;
                        }
                        if (! is_utf8) {
                            DEBUG (">> \\U %ld-byte code point turns UTF-8 ON AT byte offset %ld.\n", len, *offset)
                            is_utf8 = 1;
                        }
                    }
                    *offset = *offset + 7;

                // Else no good.
                } else {
                    free (str);
                    croak ("Unsupported escape sequence at byte offset %ld.", *offset - 1);
                }

            // Any other characters "as is", including inline UTF-8 (which JSON doesn't officially support).
            } else {

                len = UTF8SKIP (&json[*offset]);
                if (*offset + len > nbytes) {
                    free (str);
                    croak ("UTF-8 overflow at byte offset %ld.", *offset);
                }

                if ((len > 1) && ! is_utf8) {
                    DEBUG (">> UTF-8 %ld-byte inline character turns UTF-8 ON AT byte offset %ld.\n", len, *offset)
                    is_utf8 = 1;
                }

                for (STRLEN i = 0; i < len; i++) {
                    seq[i] = json[*offset + i];
                }

                // Adjust the offset.
                *offset = *offset + len;
            }

            // Do we need to re-alloc our string buffer?
            if ((str_len + len) > max_len) {
                DEBUG ("Growing string buffer up to %d bytes.\n", DEFAULT_STRING_LEN * 4)
                char *str2 = (char *) malloc (DEFAULT_STRING_LEN * 4);
                memcpy (str2, str, str_len);
                max_len = DEFAULT_STRING_LEN * 4;
                free (str);
                str = str2;
            }

            // Copy the byte(s) for this character.
            // Assume this is faster than memcpy for 1-2 byte strings.
            for (STRLEN i = 0; i < len; i++) {
                str[str_len + i] = seq[i];
            }
            str_len = str_len + len;
        }

        // Cannot mix UTF-8 and \x formatting.
        if (is_utf8 && is_binary) {
            free (str);
            croak ("Forbidden mix of 8-bit \\x (binary) with UTF-8 content in string starting at byte offset %ld.", start);
        }

        // A len = 0 tells perl to use strlen to get the length.  
        // Force a NUL terminator so that empty strings work properly.
        //
        DEBUG ("Returned string is %ld bytes.\n", str_len)
        if (str_len == 0) {
            str[0] = 0;
        }

        SV *str_sv = newSVpv (str, str_len);
        if (is_utf8) {
            SvUTF8_on (str_sv);
        }

        // NOTE: Do not call free (str).  It is handled by Perl reference counting now.

        return (str_sv);
    }

    // String only?  Stop here!
    if (flags & FLAG_STRING_ONLY) {
        return NULL;
    }

    // May it be a variable starting with "$" and followed by a non-whitespace string?
    if (ch == '$') {

        // Be nice, if variable capture is not enabled give them a clue.
        if (! vars_av) {
            croak ("Variable not permitted here starting at byte offset %ld.", *offset);
        }

        // Top-level variables don't work because the scalar is passed back by copy.  Sorry.
        if (level == 0) {
            croak ("Variable not permitted at top level, starting at byte offset %ld.", *offset);
        }

        // Note that "--", "//", "/*" will NOT be detected as the start of comment if they form part of a variable specifier.
        // Note that backspace characters will NOT be interpreted when they form part of a variable specifier.
        // Note that inline UTF-8 characters WILL be interpreted when they form part of a variable specifier.
        //
        DEBUG ("Variable capture beginning at byte offset %ld.\n", *offset);
        STRLEN start = *offset;

        // Consume the starting '$'. 
        *offset = *offset + 1;

        // Assign this as the default string size.  We will re-malloc if and when we outgrow this.
        char *str = (char *) malloc (DEFAULT_STRING_LEN);
        STRLEN max_len = DEFAULT_STRING_LEN;
        STRLEN str_len = 0;
        int is_utf8 = 0;

        // Keep absorbing non-whitespace.
        while (1) {

            // Nothing left.
            if (*offset >= nbytes) {
                free (str);
                croak ("Unterminated variable specifier beginning at byte offset %ld.", start);
            }

            // Terminating '$', we're done!
            ch = json[*offset];
            if (ch == '$') {
                *offset = *offset + 1;
                break;
            }

            // The sequence to append.
            char seq[6];
            STRLEN len = 0;


            // A backslash.
            if (ch == BACKSLASH) {
                *offset = *offset + 1;

                // Double backslash?
                if ((*offset < nbytes) && (json[*offset] == BACKSLASH)) {
                    seq[0] = BACKSLASH;
                    *offset = *offset + (len = 1);

                // Escaped double quote?
                } else if ((*offset < nbytes) && (json[*offset] == '$')) {
                    seq[0] = '$';
                    *offset = *offset + (len = 1);

                // Else no good.
                } else {
                    free (str);
                    croak ("Unsupported escape sequence at byte offset %ld.", *offset - 1);
                }

            } else {

                // Any other characters "as is", including inline UTF-8 (which JSON doesn't officially support).
                // Also including space.
                len = UTF8SKIP (&json[*offset]);
                if (*offset + len > nbytes) {
                    free (str);
                    croak ("UTF-8 overflow at byte offset %ld.", *offset);
                }

                if ((len > 1) && ! is_utf8) {
                    DEBUG (">> UTF-8 %ld-byte inline character turns UTF-8 ON AT byte offset %ld.\n", len, *offset)
                    is_utf8 = 1;
                }

                for (STRLEN i = 0; i < len; i++) {
                    seq[i] = json[*offset + i];
                }

                // Adjust the offset.
                *offset = *offset + len;                
            }

            // Do we need to re-alloc our string buffer?
            if ((str_len + len) > max_len) {
                DEBUG ("Growing string buffer up to %d bytes.\n", DEFAULT_STRING_LEN * 4)
                char *str2 = (char *) malloc (DEFAULT_STRING_LEN * 4);
                memcpy (str2, str, str_len);
                max_len = DEFAULT_STRING_LEN * 4;
                free (str);
                str = str2;
            }

            // Copy the byte(s) for this character.
            // Assume this is faster than memcpy for 1-2 byte strings.
            for (STRLEN i = 0; i < len; i++) {
                str[str_len + i] = seq[i];
            }
            str_len = str_len + len;

            // NOTE: Offset was adjusted earlier.
        }

        // Empty variable specifiers are NOT valid.
        if (str_len == 0) {
            croak ("Empty variable specifier detected at byte offset %ld.", start);
        }

        SV *str_sv = newSVpv (str, str_len);
        if (is_utf8) {
            SvUTF8_on (str_sv);
        }

        // The initial value of the variable is undef.
        SV *value_sv = newSVsv (&PL_sv_undef);

        // Initialise a new HASH.  HV's reference count is 1.
        // Also make it special-style mortal so that it doesn't leak on croak.
        HV *hv = newHV ();
        SvGETMAGIC ((SV *) hv);   

        // Fill the HASH with the name and value (reference).
        hv_store (hv, "name", 4, str_sv, 0);
        hv_store (hv, "vref", 4, newRV_inc (value_sv), 0);

        // Push the hash onto the AV.
        av_push (vars_av, newRV_noinc ((SV *) hv));

        // NOTE: Do not call free (str).  It is handled by Perl reference counting now.

        DEBUG ("Variable capture finished, now at byte offset %ld.\n", *offset);

        // The initial value of the varible is undef.
        return (value_sv);
    }

    // null is per RFC7159 section 3. Values.
    //
    // We map to the Perl undef.
    //
    if (((nbytes - *offset) >= 4) && (ch == 'n') && ! strncmp (&json[*offset], "null", 4)) {
        *offset = *offset + 4;
        return &PL_sv_undef;

    // true/false are per RFC7159 section 3. Values.
    //
    // We map to the standard Perl boolean::true/false.
    //
    } else if ((((nbytes - *offset) >= 4) && (ch == 't') && ! strncmp (&json[*offset], "true", 4)) ||
               (((nbytes - *offset) >= 5) && (ch == 'f') && ! strncmp (&json[*offset], "false", 5))) {

        int bv = (json[*offset] == 't') ? 1 : 0;
        *offset = *offset + ((json[*offset] == 't') ? 4 : 5);

        // Mark the stack and push the $self object pointer onto it.
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK (SP);
        // XPUSHs (sv_2mortal (newSVpv ("boolean", 0)));
        XPUSHs (sv_2mortal (newSViv (bv)));
        PUTBACK;

        // int rcount = call_method ("boolean", G_SCALAR);
        int rcount = call_pv ("boolean::boolean", G_SCALAR);
        SPAGAIN;

        if (rcount != 1) {
            croak ("boolean returned bad value count %d", rcount);
        }

        // Take a copy before using it.  POPs is a macro and we only want to execute it ONCE.
        SV *tf_sv = POPs;
        tf_sv = newSVsv (tf_sv);

        PUTBACK;
        FREETMPS;
        LEAVE;

        return tf_sv;

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

    // ARRAY
    } else if (ch == '[') {

        STRLEN start = *offset;

        // Consume the starting '['. 
        *offset = *offset + 1;

        // Initialise a new Array.  AV's reference count is 1.
        // Also make it special-style mortal so that it doesn't leak on croak.
        AV* av = newAV ();
        SvGETMAGIC ((SV *) av);

        SAVEMORTALIZESV (av);

        // Consume leading whitespace.
        eat_space (json, nbytes, offset);

        // End of input, array is still open.
        if (*offset >= nbytes) {
            croak ("Array element starting at byte offset %ld has no matching ']'.", start);
        }

        // Get all the elements.
        int num_elements = 0;
        while (1) {
            DEBUG ("Looking for element [%d] at byte offset %ld.\n", num_elements, *offset);

            // End of array element?
            ch = json[*offset];

            // Terminating "]", we're done!
            // Note that we allow trailing "," in our JSON arrays.
            if (ch == ']') {
                *offset = *offset + 1;
                break;
            }

            // OK, then we MUST have an element.  It may be a variable.
            SV *element_sv = json_to_perl_inner (level + 1, json, nbytes, offset, vars_av, flags);

            // I don't think it's possible that we can run out of input here.
            // We already ate all the space and checked for not end-of-input.
            // Either we find something, or we croak.  We can't return NULL.
            //
            assert (element_sv);

            // Push the SV onto the array.
            // The SV already has reference count 1 so no need to increment when we push.
            //
            // TODO: It's mortalized, so maybe it does?
            //
            av_push (av, element_sv);
            num_elements = num_elements + 1;

            // Consume trailing whitespace.
            eat_space (json, nbytes, offset);

            // End of input, array is still open.
            if (*offset >= nbytes) {
                croak ("Array element starting at byte offset %ld has no matching ']'.", start);
            }

            ch = json[*offset];
            DEBUG ("After object member, looking at '%c' at byte offset %ld.", ch, *offset);

            // Now there must be either a ']' or ','.
            // Bracket simply ends the array.
            if (ch == ']') {
                *offset = *offset + 1;
                break;
            }

            // Consume the ',' which must be present.
            if (ch != ',') {
                croak ("Expected ',' array element separator at byte offset %ld, got '%c'.", *offset, ch);
            }
            *offset = *offset + 1;

            // Consume trailing whitespace after the comma then go back for more elements.
            eat_space (json, nbytes, offset);

            // End of input, array is still open.
            if (*offset >= nbytes) {
                croak ("Array starting at byte offset %ld has no matching ']'.", start);
            }
        }                

        // Increment the reference count because we'll lose one reference as it's mortal.
        return newRV_inc ((SV *) av);

    // OBJECT
    } else if (ch == '{') {

        STRLEN start = *offset;

        // Consume the starting '{'. 
        *offset = *offset + 1;

        // Initialise a new HASH.  HV's reference count is 1.
        // Also make it special-style mortal so that it doesn't leak on croak.
        HV *hv = newHV ();
        SvGETMAGIC ((SV *) hv);   

        SAVEMORTALIZESV (hv);

        // Consume leading whitespace.
        eat_space (json, nbytes, offset);

        // End of input, object is still open.
        if (*offset >= nbytes) {
            croak ("Object starting at byte offset %ld has no matching '}'.", start);
        }

        // Get all the attribute elements.
        int num_members = 0;
        while (1) {
            DEBUG ("Looking for member [%d] at byte offset %ld.\n", num_members, *offset);

            // End of object member?
            ch = json[*offset];

            // Terminating "}", we're done!
            // Note that we allow trailing "," in our JSON objects.
            if (ch == '}') {
                *offset = *offset + 1;
                break;
            }

            // OK, first we MUST have a member name (string).  Variables are NOT allowed.
            // This is mortal, it is used only as the hash key then is gone.
            SV *name_sv = sv_2mortal (json_to_perl_inner (level + 1, json, nbytes, offset, NULL, flags | FLAG_STRING_ONLY));

            // This means we couldn't find a double-quote name.
            if (! name_sv) {
                croak ("Object name not found at byte offset %ld.", *offset);
            }

            // Consume trailing whitespace.
            eat_space (json, nbytes, offset);

            // End of input, object is still open.
            if (*offset >= nbytes) {
                croak ("Object starting at byte offset %ld has no matching '}'.", start);
            }

            // Consume the ':' which must be present.
            ch = json[*offset];
            if (ch != ':') {
                croak ("Expected ':' object member separator at byte offset %ld, got '%c'.", *offset, ch);
            }
            *offset = *offset + 1;

            // Now we MUST have a member value (string).  It may be a variable.
            SV *value_sv = json_to_perl_inner (level + 1, json, nbytes, offset, vars_av, flags);

            // STORE the HASH ENTRY.
            // Using hv_store_ent allows us to retain the UTF-8 flag on the key.
            hv_store_ent (hv, name_sv, value_sv, 0);

            // Consume trailing whitespace.
            eat_space (json, nbytes, offset);

            // End of input, object is still open.
            if (*offset >= nbytes) {
                croak ("Object starting at byte offset %ld has no matching '}'.", start);
            }

            // Now there must be either a '}' or ','.
            // Bracket simply ends the object.
            ch = json[*offset];
            if (ch == '}') {
                *offset = *offset + 1;
                break;
            }

            // Consume the ',' which must be present.
            if (ch != ',') {
                croak ("Expected ',' object member separator at byte offset %ld, got '%c'.", *offset, ch);
            }
            *offset = *offset + 1;

            // Consume trailing whitespace after the comma then go back for more members.
            eat_space (json, nbytes, offset);

            // End of input, object is still open.
            if (*offset >= nbytes) {
                croak ("Object starting at byte offset %ld has no matching '}'.", start);
            }

            num_members++;
        }                

        // Increment the reference count because we'll lose one reference as it's mortal.
        return newRV_inc ((SV *) hv);

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
#       vars_av - Optional AV reference to which we will capture vars.
#
# Returns:
#       object - The Perl object that we parsed from the JSON
#       args - Reference to an array of extracted RHS that begin with "$"
#               [ { name => <part-after-$>, ref => <ref-to-SV> } ]
###############################################################################  
void decode (json_sv, ...)
    SV * json_sv;
PPCODE:

    AV * vars_av = NULL;
    if (items >= 2) {
        SV *vars_sv = ST(1);

        if (SvROK (vars_sv) && (SvTYPE (SvRV (vars_sv)) == SVt_PVAV)) {
            vars_av = (AV *) SvRV (vars_sv);

        } else {
            croak ("If present, vars must be ARRAY reference.");
        }
    }

    STRLEN json_len;
    char *json = SvPV (json_sv, json_len);

    STRLEN offset = 0;
    SV *results = json_to_perl_inner (0, json, json_len, &offset, vars_av, 0);

    // Consume trailing whitespace.
    eat_space (json, json_len, &offset);

    // Check for trailing non-whitespace.
    if (offset < json_len) {
        sv_2mortal (results);
        croak ("Trailing non-whitespace begins at byte offset %ld.", offset);
    }

    // Should we return an <undef> here?
    if (! results) {
        croak ("No JSON content found.");
    }

    XPUSHs (sv_2mortal (results));
    XSRETURN(1);  
