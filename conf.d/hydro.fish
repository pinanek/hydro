status is-interactive || exit

set --global _hydro_git _hydro_git_$fish_pid

function $_hydro_git --on-variable $_hydro_git
    commandline --function repaint
end

function _hydro_pretty_path
    string replace --regex --all -- "(\.?[^/]{$hydro_pwd_dir_length})[^/]*/" '$1/' $argv[1] |
        string replace --regex -- '([^/]+)$' "\x1b[1m\$1\x1b[22m" |
        string replace --regex --all -- '(?!^/$)/|^$' "\x1b[2m/\x1b[22m"
end

function _hydro_pwd --on-variable PWD --on-variable hydro_ignored_git_paths --on-variable hydro_pwd_dir_length
    if test "$hydro_pwd_dir_length" = 0
        set --global _hydro_pwd (path basename $PWD)
        return
    end

    set --local dir (string replace --regex -- "^$(string escape --style=regex -- ~)" '~' $PWD)

    if ! set --query _hydro_git_root[1]
        set --global _hydro_pwd (_hydro_pretty_path $dir)
    else
        set --local git_dir (string replace --regex -- "^$(string escape --style=regex -- ~)" '~' $_hydro_git_root)
        set --local after_git (string replace -- "$git_dir" "" "$dir")

        if test -z $after_git
            set --global _hydro_pwd (_hydro_pretty_path $dir)
        else
            set --global _hydro_pwd "$(_hydro_pretty_path $git_dir)$(_hydro_pretty_path $after_git)"
        end
    end
end

function _hydro_who
    set --local show_hostname false
    set --local suffix ""
    if set --query SSH_CONNECTION
        set show_hostname true
        set suffix "$suffix (SSH)"
    else
        switch (uname)
            case Linux
                if test -r /proc/1/environ && grep -qa container=lxc /proc/1/environ
                    set show_hostname true
                end
            case FreeBSD
                if test "$(sysctl -n security.jail.jailed)" = 1
                    set show_hostname true
                end
            case SunOS
                if test "$(zonename)" != global
                    set show_hostname true
                end
        end
    end

    if test "$show_hostname" = true
        set --local short_host (
            string split --fields 1 . $hostname
        )
        set --global _hydro_who "$USER@$short_host$suffix "
    else if test "$hydro_always_show_user" = true
        set --global _hydro_who "$USER$suffix "
    else
        set --global _hydro_who ""
    end
end

function _hydro_postexec --on-event fish_postexec
    set --local last_status $pipestatus
    set --global _hydro_status "$_hydro_newline$_hydro_color_prompt$hydro_symbol_prompt"

    for code in $last_status
        if test $code -ne 0
            set --global _hydro_status "$_hydro_color_error| "(echo $last_status)" $_hydro_newline$_hydro_color_prompt$_hydro_color_error$hydro_symbol_prompt"
            break
        end
    end

    test "$CMD_DURATION" -lt $hydro_cmd_duration_threshold && set _hydro_cmd_duration && return

    set --local secs (math --scale=1 $CMD_DURATION/1000 % 60)
    set --local mins (math --scale=0 $CMD_DURATION/60000 % 60)
    set --local hours (math --scale=0 $CMD_DURATION/3600000)

    set --local out

    test $hours -gt 0 && set --local --append out $hours"h"
    test $mins -gt 0 && set --local --append out $mins"m"
    test $secs -gt 0 && set --local --append out $secs"s"

    set --global _hydro_cmd_duration "$out "
end

function _hydro_prompt --on-event fish_prompt
    set --query _hydro_status || set --global _hydro_status "$_hydro_newline$_hydro_color_prompt$hydro_symbol_prompt"
    set --query _hydro_pwd || _hydro_pwd
    set --query _hydro_who || _hydro_who

    command kill $_hydro_last_pid 2>/dev/null

    set --local git_root (command git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)

    if test "$git_root" != "$_hydro_git_root"
        set --global _hydro_git_root $git_root
        _hydro_pwd
    end

    if ! set --query _hydro_git_root[1] || contains -- "$_hydro_git_root" $hydro_ignored_git_paths
        set $_hydro_git
        return
    end

    fish --private --command "
        set branch (
            command git symbolic-ref --short HEAD 2>/dev/null ||
            command git describe --tags --exact-match HEAD 2>/dev/null ||
            command git rev-parse --short HEAD 2>/dev/null |
                string replace --regex -- '(.+)' '@\$1'
        )

        test -z \"\$$_hydro_git\" && set --universal $_hydro_git \"\$branch \"

        command git diff-index --quiet HEAD 2>/dev/null
        test \$status -eq 1 ||
            count (command git ls-files --others --exclude-standard (command git rev-parse --show-toplevel)) >/dev/null && set info \"$hydro_symbol_git_dirty\"

        for fetch in $hydro_fetch false
            command git rev-list --count --left-right @{upstream}...@ 2>/dev/null |
                read behind ahead

            switch \"\$behind \$ahead\"
                case \" \" \"0 0\"
                case \"0 *\"
                    set upstream \" $hydro_symbol_git_ahead\$ahead\"
                case \"* 0\"
                    set upstream \" $hydro_symbol_git_behind\$behind\"
                case \*
                    set upstream \" $hydro_symbol_git_ahead\$ahead $hydro_symbol_git_behind\$behind\"
            end

            set --universal $_hydro_git \"\$branch\$info\$upstream \"

            test \$fetch = true && command git fetch --no-tags 2>/dev/null
        end
    " &

    set --global _hydro_last_pid $last_pid
end

function _hydro_fish_exit --on-event fish_exit
    set --erase $_hydro_git
end

function _hydro_uninstall --on-event hydro_uninstall
    set --names |
        string replace --filter --regex -- "^(_?hydro_)" "set --erase \$1" |
        source
    functions --erase (functions --all | string match --entire --regex "^_?hydro_")
end

set --global hydro_color_normal (set_color normal)

for color in hydro_color_{pwd,git,error,prompt,duration,start,who}
    function $color --on-variable $color --inherit-variable color
        set --query $color && set --global _$color (set_color $$color)
    end && $color
end

function hydro_multiline --on-variable hydro_multiline
    if test "$hydro_multiline" = true
        set --global _hydro_newline "\n"
    else
        set --global _hydro_newline ""
    end
end && hydro_multiline

set --query hydro_color_error || set --global hydro_color_error $fish_color_error
set --query hydro_symbol_prompt || set --global hydro_symbol_prompt ❱
set --query hydro_symbol_git_dirty || set --global hydro_symbol_git_dirty •
set --query hydro_symbol_git_ahead || set --global hydro_symbol_git_ahead ↑
set --query hydro_symbol_git_behind || set --global hydro_symbol_git_behind ↓
set --query hydro_multiline || set --global hydro_multiline false
set --query hydro_pwd_dir_length || set --global hydro_pwd_dir_length 1
set --query hydro_cmd_duration_threshold || set --global hydro_cmd_duration_threshold 1000
