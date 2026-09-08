# pattern: Functional Core
# Hostname-based color computation for Starship prompt
# Extracted from eropple.zsh-theme

# Check if terminal supports truecolor
_supports_truecolor() {
    # Explicit truecolor advertisement
    [[ "$COLORTERM" == "truecolor" || "$COLORTERM" == "24bit" ]] && return 0

    # Known truecolor terminals by TERM
    [[ "$TERM" == "xterm-ghostty" ]] && return 0

    # Force truecolor via env var (useful for SSH)
    [[ "$FORCE_TRUECOLOR" == "1" ]] && return 0

    # Modern terminals with 256color usually support truecolor
    # but be conservative - only enable if user opts in
    return 1
}

# Convert HSL to RGB hex
# H: 0-360, S: 0-100, L: 0-100
_hsl_to_rgb() {
    local h=$1 s=$2 l=$3

    # Normalize to 0-1 range (using integer math scaled by 1000)
    local s1=$((s * 10))  # 0-1000
    local l1=$((l * 10))  # 0-1000

    local c=$(( (1000 - (l1 > 500 ? 2*l1 - 1000 : 1000 - 2*l1)) * s1 / 1000 ))
    local x=$(( c * (1000 - ((h * 1000 / 60 % 2000) - 1000)) / 1000 ))
    [[ $x -lt 0 ]] && x=$((-x))
    local m=$((l1 - c / 2))

    local r1 g1 b1
    if   (( h < 60 ));  then r1=$c; g1=$x; b1=0
    elif (( h < 120 )); then r1=$x; g1=$c; b1=0
    elif (( h < 180 )); then r1=0;  g1=$c; b1=$x
    elif (( h < 240 )); then r1=0;  g1=$x; b1=$c
    elif (( h < 300 )); then r1=$x; g1=0;  b1=$c
    else                     r1=$c; g1=0;  b1=$x
    fi

    local r=$(( (r1 + m) * 255 / 1000 ))
    local g=$(( (g1 + m) * 255 / 1000 ))
    local b=$(( (b1 + m) * 255 / 1000 ))

    # Clamp to 0-255
    (( r < 0 )) && r=0; (( r > 255 )) && r=255
    (( g < 0 )) && g=0; (( g > 255 )) && g=255
    (( b < 0 )) && b=0; (( b > 255 )) && b=255

    printf "#%02x%02x%02x" $r $g $b
}

# Compute hostname-based color using HSL for better spread
# Uses truecolor RGB if supported, otherwise bright 256-colors
_hostname_color() {
    # Allow override via environment variable
    if [[ -n "$PROMPT_HOST_COLOR" ]]; then
        echo "$PROMPT_HOST_COLOR"
        return
    fi

    # Hash the hostname to get consistent values
    local hash=$(echo -n "$HOST" | shasum -a 256 | cut -f1 -d' ')

    if _supports_truecolor; then
        # Use hash to pick hue (0-360), keep saturation and lightness fixed
        # This spreads colors evenly across the spectrum
        local hash_val=$((0x${hash:0:4}))  # 16 bits = 0-65535
        local hue=$((hash_val % 360))

        # Apply optional offset to avoid collisions (set in ~/.zshrc before sourcing)
        # e.g., PROMPT_HUE_OFFSET=60 shifts the color by 60 degrees
        if [[ -n "$PROMPT_HUE_OFFSET" ]]; then
            hue=$(( (hue + PROMPT_HUE_OFFSET) % 360 ))
        fi

        local saturation=75  # Vivid but not harsh
        local lightness=70   # Bright enough to read on dark bg

        _hsl_to_rgb $hue $saturation $lightness
    else
        # 256-color fallback: use only bright colors from 6x6x6 cube
        local hash_val=$((0x${hash: -2}))
        local r g b
        local -a bright_colors

        for r in {0..5}; do
            for g in {0..5}; do
                for b in {0..5}; do
                    # Include if at least one component is 4 or 5 (bright)
                    if [[ $r -ge 4 || $g -ge 4 || $b -ge 4 ]]; then
                        bright_colors+=($((16 + 36 * r + 6 * g + b)))
                    fi
                done
            done
        done

        # Pick from bright colors array
        echo ${bright_colors[$((hash_val % ${#bright_colors[@]}))]}
    fi
}

# Compute complementary color for @ and $ symbols
# Shifts hue by 150 degrees for a distinct but harmonious color
_complementary_color() {
    local base_color=$1

    # Allow override via environment variable
    if [[ -n "$PROMPT_SYMBOL_COLOR" ]]; then
        echo "$PROMPT_SYMBOL_COLOR"
        return
    fi

    if _supports_truecolor; then
        # Get the original hue and shift it
        local hash=$(echo -n "$HOST" | shasum -a 256 | cut -f1 -d' ')
        local hash_val=$((0x${hash:0:4}))
        local hue=$((hash_val % 360))

        # Apply same offset as hostname color
        if [[ -n "$PROMPT_HUE_OFFSET" ]]; then
            hue=$(( (hue + PROMPT_HUE_OFFSET) % 360 ))
        fi

        # Shift hue by 150 degrees (between triadic and complementary)
        local comp_hue=$(( (hue + 150) % 360 ))

        _hsl_to_rgb $comp_hue 75 70
    else
        # 256-color: convert to RGB cube position and rotate
        local cube_pos=$((base_color - 16))

        # Extract R, G, B indices from 6x6x6 cube
        local r=$((cube_pos / 36))
        local g=$(((cube_pos % 36) / 6))
        local b=$((cube_pos % 6))

        # Rotate channels: RGB -> BRG
        local comp_r=$b
        local comp_g=$r
        local comp_b=$g

        # Convert back to color code
        echo $((16 + 36 * comp_r + 6 * comp_g + comp_b))
    fi
}

# Compute colors and generate Starship config
# Run at shell startup to compute once
export STARSHIP_HOST_COLOR="$(_hostname_color)"
export STARSHIP_SYMBOL_COLOR="$(_complementary_color "$STARSHIP_HOST_COLOR")"

# Generate starship.toml from template with colors baked in
_generate_starship_config() {
    local template="$ZSH_NG/starship.toml.template"
    local output="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
    local output_dir="$(dirname "$output")"

    # Ensure config directory exists
    [[ -d "$output_dir" ]] || mkdir -p "$output_dir"

    # Only regenerate if template is newer or colors changed
    local color_hash="${STARSHIP_HOST_COLOR}:${STARSHIP_SYMBOL_COLOR}"
    local cache_file="$output_dir/.starship_color_hash"
    local cached_hash=""
    [[ -f "$cache_file" ]] && cached_hash="$(cat "$cache_file")"

    if [[ ! -f "$output" || "$template" -nt "$output" || "$color_hash" != "$cached_hash" ]]; then
        sed -e "s/{{HOST_COLOR}}/$STARSHIP_HOST_COLOR/g" \
            -e "s/{{SYMBOL_COLOR}}/$STARSHIP_SYMBOL_COLOR/g" \
            "$template" > "$output"
        echo "$color_hash" > "$cache_file"
    fi
}

_generate_starship_config
