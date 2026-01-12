pub fn script() []const u8 {
    return
        \\# zing bash integration
        \\# shellcheck shell=bash
        \\
        \\__zing_query() {
        \\  command zing query "$@"
        \\}
        \\
        \\z() {
        \\  local result
        \\  result="$(__zing_query "$@")" || return $?
        \\  if [ -n "$result" ]; then
        \\    cd "$result" && command zing add "$PWD"
        \\  fi
        \\}
        \\
        \\zi() {
        \\  local result
        \\  result="$(command zing interactive "$@")" || return $?
        \\  if [ -n "$result" ]; then
        \\    cd "$result" && command zing add "$PWD"
        \\  fi
        \\}
        \\
        \\__zing_cd() {
        \\  builtin cd "$@" && command zing add "$PWD"
        \\}
        \\
        \\if ! command -v _zing_zcd_wrapped >/dev/null 2>&1; then
        \\  alias _zing_zcd_wrapped=true
        \\  alias zcd='__zing_cd'
        \\fi
        \\
        \\_zing_complete() {
        \\  COMPREPLY=()
        \\}
        \\complete -F _zing_complete z zi zing
        \\
    ;
}
