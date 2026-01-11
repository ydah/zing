pub fn script() []const u8 {
    return
        \\# zing fish integration
        \\
        \\function z
        \\  set -l result (command zing query $argv)
        \\  if test -n "$result"
        \\    cd "$result"; and command zing add "$PWD"
        \\  end
        \\end
        \\
        \\function zi
        \\  set -l result (command zing interactive $argv)
        \\  if test -n "$result"
        \\    cd "$result"; and command zing add "$PWD"
        \\  end
        \\end
        \\
        \\function cd --wraps=builtin cd
        \\  builtin cd $argv; and command zing add "$PWD"
        \\end
        \\
        \\complete -c zing -f
        \\complete -c z -f
        \\complete -c zi -f
        \\
    ;
}
