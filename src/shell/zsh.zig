pub fn script() []const u8 {
    return
        \\# zing zsh integration
        \\
        \\__zing_query() {
        \\  command zing query "$@"
        \\}
        \\
        \\z() {
        \\  local result
        \\  result="$(__zing_query "$@")" || return $?
        \\  if [[ -n "$result" ]]; then
        \\    cd "$result" && command zing add "$PWD"
        \\  fi
        \\}
        \\
        \\zi() {
        \\  local result
        \\  result="$(command zing interactive "$@")" || return $?
        \\  if [[ -n "$result" ]]; then
        \\    cd "$result" && command zing add "$PWD"
        \\  fi
        \\}
        \\
        \\__zing_cd() {
        \\  builtin cd "$@" && command zing add "$PWD"
        \\}
        \\
        \\if [[ -z "$__ZING_ZCD_WRAPPED" ]]; then
        \\  __ZING_ZCD_WRAPPED=1
        \\  alias zcd='__zing_cd'
        \\fi
        \\
        \\_zing_complete() {
        \\  reply=()
        \\}
        \\compdef _zing_complete z zi zing
        \\
    ;
}
