#
# bats-support - Supporting library for Bats test helpers
#
# Written in 2016 by Zoltan Tombol <zoltan dot tombol at gmail dot com>
#

#
# output.bash
# -----------
#
# Private functions implementing output formatting. Used by public
# helper functions.
#

# Print a message to the standard error. When no parameters are
# specified, the message is read from the standard input.
#
# Globals:
#   none
# Arguments:
#   $@ - [=STDIN] message
# Returns:
#   none
# Inputs:
#   STDIN - [=$@] message
# Outputs:
#   STDERR - message
batslib_err() {
  { if (( $# > 0 )); then
      echo "$@"
    else
      PATH="$BATS_SAVED_PATH" command cat -
    fi
  } >&2
}

# Count the number of lines in the given string.
# If the string has a trailing newline, it is interpretted as being generated with `run --keep-empty-lines` or similar.
# This function will then read and count all empty lines and trailing newlines.
#
# Globals:
#   none
# Arguments:
#   $1 - string
# Returns:
#   none
# Outputs:
#   STDOUT - number of lines
batslib_count_lines() {
  local -r input="$1"

  local line=''
  local -i n_lines=0
  # Read and count each line, until the last line (handled below).
  while IFS='' read -r line; do
    (( ++n_lines ))
  done < <(printf '%s' "$input")
  # If there's a detectable trailing newline, it's there on purpose (e.g. `run --keep-empty-lines`),
  # then empty lines must be properly handled.
  # Or, if the last line was not empty, it needs to be counted.
  if [[ "${input: -1}" = $'\n' ]] || [[ -n "$line" ]]; then
    # Increment for the EOF (not captured by the loop above).
    (( ++n_lines ))
  fi

  echo "$n_lines"
}

# Determine whether all strings are single-line.
#
# Globals:
#   none
# Arguments:
#   $@ - strings
# Returns:
#   0 - all strings are single-line
#   1 - otherwise
batslib_is_single_line() {
  for string in "$@"; do
    (( $(batslib_count_lines "$string") > 1 )) && return 1
  done
  return 0
}

# Determine the length of the longest key that has a single-line value.
#
# This function is useful in determining the correct width of the key
# column in two-column format when some keys may have multi-line values
# and thus should be excluded.
#
# Globals:
#   none
# Arguments:
#   $odd - key
#   $even - value of the previous key
# Returns:
#   none
# Outputs:
#   STDOUT - length of longest key
batslib_get_max_single_line_key_width() {
  local -i max_len=-1
  while (( $# != 0 )); do
    local -i key_len="${#1}"
    batslib_is_single_line "$2" && (( key_len > max_len )) && max_len="$key_len"
    shift 2
  done
  echo "$max_len"
}

# Print key-value pairs in two-column format.
#
# Keys are displayed in the first column, and their corresponding values
# in the second. To evenly line up values, the key column is fixed-width
# and its width is specified with the first parameter (possibly computed
# using `batslib_get_max_single_line_key_width').
#
# Globals:
#   none
# Arguments:
#   $1 - width of key column
#   $even - key
#   $odd - value of the previous key
# Returns:
#   none
# Outputs:
#   STDOUT - formatted key-value pairs
batslib_print_kv_single() {
  local -ir col_width="$1"; shift
  while (( $# != 0 )); do
    printf '%-*s : %s\n' "$col_width" "$1" "$2"
    shift 2
  done
}

# Print key-value pairs in multi-line format.
#
# The key is displayed first with the number of lines of its
# corresponding value in parenthesis. Next, starting on the next line,
# the value is displayed. For better readability, it is recommended to
# indent values using `batslib_prefix'.
#
# Globals:
#   none
# Arguments:
#   $odd - key
#   $even - value of the previous key
# Returns:
#   none
# Outputs:
#   STDOUT - formatted key-value pairs
batslib_print_kv_multi() {
  while (( $# != 0 )); do
    printf '%s (%d lines):\n' "$1" "$( batslib_count_lines "$2" )"
    printf '%s\n' "$2"
    shift 2
  done
}

# Print all key-value pairs in either two-column or multi-line format
# depending on whether all values are single-line.
#
# If all values are single-line, print all pairs in two-column format
# with the specified key column width (identical to using
# `batslib_print_kv_single').
#
# Otherwise, print all pairs in multi-line format after indenting values
# with two spaces for readability (identical to using `batslib_prefix'
# and `batslib_print_kv_multi'). For each value, if it contains a trailing
# newline, it will be printed keeping all empty lines / trailing newlines.
#
# Globals:
#   none
# Arguments:
#   $1 - width of key column (for two-column format)
#   $even - key
#   $odd - value of the previous key
# Returns:
#   none
# Outputs:
#   STDOUT - formatted key-value pairs
batslib_print_kv_single_or_multi() {
  local -ir width="$1"; shift
  local -a pairs=( "$@" )

  local -a values=()
  local -i i
  for (( i=1; i < ${#pairs[@]}; i+=2 )); do
    values+=( "${pairs[$i]}" )
  done

  if batslib_is_single_line "${values[@]}"; then
    batslib_print_kv_single "$width" "${pairs[@]}"
  else
    local -i i
    for (( i=1; i < ${#pairs[@]}; i+=2 )); do
      # If value has trailing newline, keep it.
      if [[ "${pairs[$i]: -1}" = $'\n' ]]; then
        pairs[$i]="$( batslib_prefix --keep-empty-lines < <(printf '%s' "${pairs[$i]}") )"
      else
        pairs[$i]="$( batslib_prefix < <(printf '%s' "${pairs[$i]}") )"
      fi
    done
    batslib_print_kv_multi "${pairs[@]}"
  fi
}

# Prefix each line read from the standard input with the given string.
#
# Globals:
#   none
# Arguments:
#   --keep-empty-lines - optional. preserves empty lines and trailing newlines.
#   $1 - [=  ] prefix string
# Returns:
#   none
# Inputs:
#   STDIN - lines
# Outputs:
#   STDOUT - prefixed lines
batslib_prefix() {
  local -i keep_empty_lines=0
  if [ "${1-}" = '--keep-empty-lines' ]; then
    keep_empty_lines=1
    shift
  fi
  local -r prefix="${1:-  }"

  local line=''
  local -i lines_read=0
  # Read and print each line, until the last line (handled below).
  while IFS='' read -r line; do
    printf '%s%s\n' "$prefix" "$line"
    (( ++lines_read ))
  done
  # Print for the last line with EOF (not captured by the loop above).
  # The last read line must be non-empty, or `keep_empty_lines` with non-empty stdin.
  if (( keep_empty_lines )) && (( lines_read > 0 )) || [[ -n "$line" ]]; then
    printf '%s%s\n' "$prefix" "$line"
  fi
}

# Mark select lines of the text read from the standard input by
# overwriting their beginning with the given string.
#
# Usually the input is indented by a few spaces using `batslib_prefix'
# first.
#
# Globals:
#   none
# Arguments:
#   --keep-empty-lines - optional. preserves empty lines and trailing newlines.
#   $1 - marking string
#   $@ - indices (zero-based) of lines to mark
# Returns:
#   none
# Inputs:
#   STDIN - lines
# Outputs:
#   STDOUT - lines after marking
batslib_mark() {
  local -i keep_empty_lines=0
  if [ "${1-}" = '--keep-empty-lines' ]; then
    keep_empty_lines=1
    shift
  fi
  local -r symbol="$1"; shift
  # Sort line numbers.
  set -- $( sort -nu <<< "$( printf '%d\n' "$@" )" )

  local line=''
  local -i idx=0
  # Read and print each line, until the last line (handled below).
  while IFS='' read -r line; do
    if (( ${1:--1} == idx )); then
      printf '%s\n' "${symbol}${line:${#symbol}}"
      shift
    else
      printf '%s\n' "$line"
    fi
    (( ++idx ))
  done
  # Print for the last line with EOF (not captured by the loop above).
  # The last read line must be non-empty, or `keep_empty_lines` with non-empty stdin.
  if (( keep_empty_lines )) && (( idx > 0 )) || [[ -n "$line" ]]; then
    if (( ${1:--1} == idx )); then
      printf '%s\n' "${symbol}${line:${#symbol}}"
      shift
    else
      printf '%s\n' "$line"
    fi
  fi
}

# Enclose the input text in header and footer lines.
#
# The header contains the given string as title. The output is preceded
# and followed by an additional newline to make it stand out more.
#
# Globals:
#   none
# Arguments:
#   $1 - title
# Returns:
#   none
# Inputs:
#   STDIN - text
# Outputs:
#   STDOUT - decorated text
batslib_decorate() {
  echo
  echo "-- $1 --"
  PATH="$BATS_SAVED_PATH" command cat -
  echo '--'
  echo
}
