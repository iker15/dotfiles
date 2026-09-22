# Colores del texto que escribes (comandos, parámetros...) según la versión oscura del esquema de
# Caelestia, que sale del fondo de pantalla. Se recargan solos si cambias de fondo.
function __scheme_colours --on-event fish_prompt
    set -l f ~/.local/state/caelestia/dark/scheme.json
    test -r $f; or return
    set -l t (path mtime $f)
    test "$t" = "$__scheme_mtime"; and return
    set -g __scheme_mtime $t

    set -l json (string join '' < $f)
    function __c --no-scope-shadowing
        string match -rg "\"$argv[1]\": \"([0-9a-fA-F]{6})\"" -- $json
    end

    set -g fish_color_command (__c primary) --bold
    set -g fish_color_keyword (__c primary)
    set -g fish_color_param (__c secondary)
    set -g fish_color_option (__c tertiary)
    set -g fish_color_quote (__c tertiaryFixedDim)
    set -g fish_color_escape (__c tertiary)
    set -g fish_color_redirection (__c secondaryFixedDim)
    set -g fish_color_operator (__c tertiary)
    set -g fish_color_end (__c outline)
    set -g fish_color_error (__c error)
    set -g fish_color_comment (__c outline) --italics
    set -g fish_color_autosuggestion (__c outline)
    set -g fish_color_valid_path --underline
    set -g fish_color_search_match --background=(__c surfaceContainerHighest)
    set -g fish_color_selection --background=(__c surfaceContainerHighest)
    set -g fish_pager_color_prefix (__c primary) --bold
    set -g fish_pager_color_completion (__c onSurface)
    set -g fish_pager_color_description (__c outline)
    set -g fish_pager_color_progress (__c tertiary)
    functions -e __c
end
__scheme_colours
