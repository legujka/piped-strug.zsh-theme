# Tree characters
TREE_HEADER_START_RAW="╭─"
TREE_VERTICAL_RAW="│"
TREE_BRANCH_RAW="├"
TREE_CORNER_RAW="╰"

# Colors (ANSI escape codes for printf, %F{} for PROMPT)
TREE_COLOR=$'\e[32m'       # Green for tree characters
HEADER_GIT_COLOR=$'\e[34m' # Blue for git branch
HEADER_RESET=$'\e[0m'

# For printf (raw ANSI)
TREE_HEADER_START="$TREE_COLOR$TREE_HEADER_START_RAW$HEADER_RESET"
TREE_VERTICAL="$TREE_COLOR$TREE_VERTICAL_RAW$HEADER_RESET"
TREE_BRANCH="$TREE_COLOR$TREE_BRANCH_RAW$HEADER_RESET"
TREE_CORNER="$TREE_COLOR$TREE_CORNER_RAW$HEADER_RESET"

# For PROMPT (with %{%} escaping so ZSH calculates cursor position correctly)
TREE_HEADER_START_P="%{$TREE_COLOR%}$TREE_HEADER_START_RAW%{$HEADER_RESET%}"
TREE_CORNER_P="%{$TREE_COLOR%}$TREE_CORNER_RAW%{$HEADER_RESET%}"

PROMPT_SYMBOL_SUCCESS_ANSI=$'\e[32m' # Green
PROMPT_SYMBOL_ERROR_ANSI=$'\e[31m'   # Red

# Colors for prompt (using ZSH %F{color} format)
PROMPT_USER_COLOR='green'     # Color for user@host in prompt
PROMPT_DIR_COLOR='yellow'     # Color for directory in prompt
PROMPT_SYMBOL_SUCCESS='green' # Color for $ when last command succeeded
PROMPT_SYMBOL_ERROR='red'     # Color for $ when last command failed

# Prompt symbols (can be different for active vs executed)
PROMPT_SYMBOL_ACTIVE='$'   # Symbol for active prompt (where you type)
PROMPT_SYMBOL_EXECUTED='$' # Symbol for executed commands

# Git display
GIT_SHOW_BRANCH=true # Show git branch in header

# Empty line behavior
SHOW_VERTICAL_ON_EMPTY_ENTER=true # Show │ when pressing Enter on empty line
SHOW_VERTICAL_ON_EMPTY_CTRLC=true # Show │ when pressing Ctrl+C on empty line

# Command detection
SHOW_CORNER_ON_DIR_CHANGE=true # Show ╰ for cd/popd commands
SHOW_CORNER_ON_GIT_CHANGE=true # Show ╰ for git checkout/switch

# Output indentation
OUTPUT_INDENT_RAW="│  " # Prefix for command output
OUTPUT_INDENT="$TREE_COLOR$OUTPUT_INDENT_RAW$HEADER_RESET"

# Skip output redirection for these commands (comma-separated)
SKIP_COMMANDS="vim,nvim,vi,nano,top,htop,ssh,fzf,lazygit,claude"

# ================================================= #
# INTERNAL VARIABLES - Don't modify below this line #
# ================================================= #
typeset -g _TREE_LAST_CONTEXT=""
typeset -g _TREE_WAS_EMPTY=0
typeset -g _TREE_INTERRUPTED=0
typeset -g _TREE_STDOUT_BAK=""
typeset -g _TREE_STDERR_BAK=""
typeset -g _TREE_CURRENT_BRANCH=""

# Convert skip commands to array
_SKIP_CMDS=(${(s:,:)SKIP_COMMANDS})

# Check if zoxide is available
_TREE_HAS_ZOXIDE=$(( $+commands[zoxide] ))

# Internal color variables (derived from config)
_TC_GIT="${HEADER_GIT_COLOR}"
_TC_RESET="${HEADER_RESET}"

_TP_USER="%F{${PROMPT_USER_COLOR}}"
_TP_DIR="%F{${PROMPT_DIR_COLOR}}"
_TP_SUCCESS="%F{${PROMPT_SYMBOL_SUCCESS}}"
_TP_ERROR="%F{${PROMPT_SYMBOL_ERROR}}"
_TP_RESET='%f'

_tree_update_branch() {
    _TREE_CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
}

_tree_git_info() {
    ${GIT_SHOW_BRANCH} || return
    # Use %{%} escaping for PROMPT compatibility
    [[ -n "$_TREE_CURRENT_BRANCH" ]] && printf " %%{${_TC_GIT}%%}on %s%%{${_TC_RESET}%%}" "$_TREE_CURRENT_BRANCH"
}

_tree_context() {
    printf '%s:%s' "$PWD" "$_TREE_CURRENT_BRANCH"
}

_tree_restore_fds() {
    if [[ -n "$_TREE_STDOUT_BAK" ]] && { true >&$_TREE_STDOUT_BAK } 2>/dev/null; then
        # Flush any pending output before restoring
        : >&1 2>&1
        exec 1>&$_TREE_STDOUT_BAK 2>&$_TREE_STDERR_BAK
        exec {_TREE_STDOUT_BAK}>&- {_TREE_STDERR_BAK}>&-
        unset _TREE_STDOUT_BAK _TREE_STDERR_BAK
        # Small delay to let sed processes finish
        sleep 0.01
    fi
}

_tree_should_skip() {
    local cmd="$1"
    for skip_cmd in "${_SKIP_CMDS[@]}"; do
        if [[ "$cmd" == ${~skip_cmd}* ]]; then
            return 0
        fi
    done
    return 1
}

TRAPINT() {
    _tree_restore_fds

    if [[ -n "${BUFFER//[[:space:]]/}" ]]; then
        local pchar_ansi=$'\e[31m'
        local first_line="${BUFFER%%$'\n'*}"
        # Just print on current line, let terminal handle the rest
        print -n '\r\e[2K'"${TREE_BRANCH}${pchar_ansi}${PROMPT_SYMBOL_EXECUTED}${HEADER_RESET} ${first_line} ^C"
    else
        ${SHOW_VERTICAL_ON_EMPTY_CTRLC} && print -n '\r\e[2K'"${TREE_VERTICAL}"
    fi

    _TREE_INTERRUPTED=1
    zle -U ""
    return 130
}

_tree_accept_line() {
    [[ -z "${BUFFER//[[:space:]]/}" ]] && _TREE_WAS_EMPTY=1 || _TREE_WAS_EMPTY=0
    _TREE_INTERRUPTED=0
    zle .accept-line
}

_tree_preexec() {
    _tree_restore_fds
    _TREE_WAS_EMPTY=0
    _TREE_INTERRUPTED=0
    local cmd="$1"

    local prefix="${TREE_BRANCH}"
    local pchar_ansi="${PROMPT_SYMBOL_SUCCESS_ANSI}"

    if ${SHOW_CORNER_ON_DIR_CHANGE}; then
        if [[ "$cmd" =~ ^(cd|pushd)([[:space:]]+(.*)|$) ]]; then
            local target="${match[3]//[[:space:]]/}"

            [[ -z "$target" || "$target" == "~" ]] && target="$HOME"

            local abs_target
            if [[ "$target" == "." ]]; then abs_target="$PWD"
            elif [[ "$target" == ".." ]]; then abs_target="$(dirname "$PWD")"
            elif [[ "$target" == "-" ]]; then abs_target="$OLDPWD"
            elif [[ "$target" == /* ]]; then abs_target="$target"
            elif [[ -d "$PWD/$target" ]]; then abs_target="$PWD/$target"
            elif (( _TREE_HAS_ZOXIDE )); then
                abs_target=$(zoxide query "$target" 2>/dev/null)
            fi

            [[ -n "$abs_target" ]] && abs_target="${abs_target:A}"

            if [[ -n "$abs_target" && "$abs_target" != "$PWD" ]]; then
                prefix="${TREE_CORNER}"
            fi
        elif (( _TREE_HAS_ZOXIDE )) && [[ "$cmd" =~ ^(z|zi)[[:space:]]+(.+)$ ]]; then
            local z_query="${match[2]}"
            local z_target=$(zoxide query "$z_query" 2>/dev/null)
            if [[ -n "$z_target" && "${z_target:A}" != "$PWD" ]]; then
                prefix="${TREE_CORNER}"
            fi
        elif [[ "$cmd" == "popd" ]]; then
            prefix="${TREE_CORNER}"
        fi
    fi
    
    if ${SHOW_CORNER_ON_GIT_CHANGE}; then
        if [[ "$cmd" =~ ^git[[:space:]]+(checkout|switch)[[:space:]]+([^[:space:]-][^[:space:]]*)([[:space:]]|$) ]]; then
            local target_branch="${match[2]}"
            local current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
            if [[ -n "$current_branch" && "$target_branch" != "$current_branch" ]]; then
                prefix="${TREE_CORNER}"
            fi
        fi
    fi

    printf '\e[1A\r%s%s%s%s \e[1B\r' "$prefix" "$pchar_ansi" "${PROMPT_SYMBOL_EXECUTED}" "${HEADER_RESET}"

    _tree_should_skip "$cmd" && return

    exec {_TREE_STDOUT_BAK}>&1 {_TREE_STDERR_BAK}>&2

    local indent="${OUTPUT_INDENT}"
    [[ "$prefix" == "${TREE_CORNER}" ]] && indent="   "

    exec 1> >(sed -u "s/^/${indent}/") \
         2> >(sed -u "s/^/${indent}/" >&2)
}

_tree_set_prompt() {
    local last_exit=$?
    _tree_restore_fds
    _tree_update_branch


    local current_context="$(_tree_context)"
    
    local pchar="${_TP_SUCCESS}${PROMPT_SYMBOL_ACTIVE}${_TP_RESET}"

    if [[ "$current_context" != "$_TREE_LAST_CONTEXT" ]]; then
        _TREE_LAST_CONTEXT="$current_context"
        PROMPT="${TREE_HEADER_START_P}${_TP_USER}%n@%m${_TP_RESET} ${_TP_DIR}in %~${_TP_RESET}$(_tree_git_info)
${TREE_CORNER_P}${pchar} "

    elif [[ $_TREE_INTERRUPTED -eq 1 ]]; then
        PROMPT="${TREE_CORNER_P}${pchar} "
        _TREE_INTERRUPTED=0

    elif [[ $_TREE_WAS_EMPTY -eq 1 ]] && ${SHOW_VERTICAL_ON_EMPTY_ENTER}; then
        printf '\e[1A\r\e[2K%s\n' "${TREE_VERTICAL}"
        PROMPT="${TREE_CORNER_P}${pchar} "

    else
        PROMPT="${TREE_CORNER_P}${pchar} "
    fi
    
    _TREE_WAS_EMPTY=0
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _tree_preexec
add-zsh-hook precmd _tree_set_prompt
zle -N accept-line _tree_accept_line

# Set environment variables for colored output through pipes
export CLICOLOR_FORCE=1      # BSD/macOS ls, grep, etc.
export GIT_PAGER_IN_USE=1    # git colors
export FORCE_COLOR=1         # Node.js, npm, yarn, chalk-based tools
export COLORTERM=truecolor   # Modern CLI tools
