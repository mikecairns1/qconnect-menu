#!/bin/bash
# q-menu.sh - A menu-driven bash script for AWS Q in Connect
# --- Configuration and State Variables ---
AWS_REGION="us-east-1"
ASSISTANT_ID=""
KNOWLEDGE_BASE_ID=""
CONTENT_ID=""
SESSION_ID=""

# --- Color Codes for UI ---
C_BLUE="\033[0;34m"
C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_YELLOW="\033[0;33m"
C_NC="\033[0m" # No Color

# --- Prerequisite Check ---
# Ensures aws and jq are installed before running.
check_dependencies() {
    for cmd in aws jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${C_RED}Error: Required command '$cmd' is not installed. Please install it and try again.${C_NC}"
            exit 1
        fi
    done
}

# --- Helper Functions ---

# Displays the current state (stored IDs) at the top of each menu.
print_state() {
    clear
    echo -e "${C_BLUE}================ AWS Q in Connect Menu ===================${C_NC}"
    echo -e "Region: ${C_YELLOW}${AWS_REGION}${C_NC}"
    echo -e "--------------------------------------------------------"
    echo -e "Current Assistant ID: ${C_GREEN}${ASSISTANT_ID:-Not Set}${C_NC}"
    echo -e "Current Knowledge Base ID: ${C_GREEN}${KNOWLEDGE_BASE_ID:-Not Set}${C_NC}"
    echo -e "Current Content ID: ${C_GREEN}${CONTENT_ID:-Not Set}${C_NC}"
    echo -e "Current Session ID: ${C_GREEN}${SESSION_ID:-Not Set}${C_NC}"
    echo -e "${C_BLUE}========================================================${C_NC}"
}

# Generic function to select a resource from a list.
# Arguments: $1=resource_name (e.g., "assistant"), $2=list_command, $3=jq_filter for name, $4=jq_filter for ID
select_resource() {
    local resource_name="$1"
    local list_command="$2"
    local name_filter="$3"
    local id_filter="$4"
    
    echo -e "Fetching list of ${resource_name}s..."
    local resource_list
    resource_list=$(eval "$list_command --region $AWS_REGION")
    
    if [[ -z "$resource_list" || $(echo "$resource_list" | jq ".${resource_name}Summaries | length") -eq 0 ]]; then
        echo -e "${C_RED}No ${resource_name}s found in region ${AWS_REGION}.${C_NC}"
        return 1
    fi

    echo -e "Please select a ${resource_name}:"
    echo "$resource_list" | jq -r ".${resource_name}Summaries[] | \"\(.name // .${resource_name}Id) | ID: \(.${resource_name}Id)\"" | cat -n
    
    local choice
    read -p "Enter number: " choice
    
    local selected_json
    selected_json=$(echo "$resource_list" | jq -r ".${resource_name}Summaries[${choice}-1]")
    
    if [[ -z "$selected_json" || "$selected_json" == "null" ]]; then
        echo -e "${C_RED}Invalid selection.${C_NC}"
        return 1
    fi

    local selected_id
    selected_id=$(echo "$selected_json" | jq -r "$id_filter")
    echo -e "${C_GREEN}${resource_name} with ID ${selected_id} selected.${C_NC}"
    
    # Dynamically set the global variable (e.g., ASSISTANT_ID)
    declare -g "$(echo ${resource_name^^} | sed 's/-/_/g')_ID"="$selected_id"
    return 0
}

# Specific selection functions
select_assistant() { [[ -z "$ASSISTANT_ID" ]] && select_resource "assistant" "aws qconnect list-assistants" ".name" ".assistantId"; }
select_knowledge_base() { [[ -z "$KNOWLEDGE_BASE_ID" ]] && select_resource "knowledgeBase" "aws qconnect list-knowledge-bases" ".name" ".knowledgeBaseId"; }
select_content() {
    select_knowledge_base || return 1
    [[ -z "$CONTENT_ID" ]] && select_resource "content" "aws qconnect list-contents --knowledge-base-id $KNOWLEDGE_BASE_ID" ".title" ".contentId"
}


# Prompts user for confirmation before executing destructive actions.
confirm_action() {
    read -p "Are you sure you want to proceed? [y/N] " response
    [[ "$response" =~ ^[yY]$ ]]
}

# Pause and wait for user to press Enter.
press_enter_to_continue() {
    read -p "Press [Enter] to return to the main menu..."
}


# --- API Command Functions ---

# CREATE Commands
create_assistant() {
    read -p "Enter assistant name: " name
    read -p "Enter assistant description (optional): " description
    echo "Creating assistant..."

    # Build the command in an array. This is best practice for handling arguments.
    local cmd=(aws qconnect create-assistant --name "$name" --type AGENT --region "$AWS_REGION")
    
    # Only add the --description flag if the user entered text for it.
    if [[ -n "$description" ]]; then
        cmd+=(--description "$description")
    fi

    # Execute the command and capture output
    local result
    result=$("${cmd[@]}" 2>&1) # Capture both stdout and stderr

    # Check the exit code of the AWS command
    if [[ $? -eq 0 ]]; then
        echo "$result" | jq '.'
        ASSISTANT_ID=$(echo "$result" | jq -r '.assistant.assistantId')
        echo -e "${C_GREEN}Assistant created. ID ${ASSISTANT_ID} is now set.${C_NC}"
    else
        # If the command failed, print the error message from AWS
        echo -e "${C_RED}Failed to create assistant. AWS API returned an error:${C_NC}"
        echo "$result"
    fi
}

create_knowledge_base() {
    read -p "Enter Knowledge Base name: " name
    echo "Creating Knowledge Base..."
    local result
    result=$(aws qconnect create-knowledge-base --name "$name" --region "$AWS_REGION")
    echo "$result" | jq '.'
    KNOWLEDGE_BASE_ID=$(echo "$result" | jq -r '.knowledgeBase.knowledgeBaseId')
    echo -e "${C_GREEN}Knowledge Base created. ID ${KNOWLEDGE_BASE_ID} is now set.${C_NC}"
}

# GET Commands
get_assistant() {
    select_assistant || return 1
    echo "Getting details for assistant ID: ${ASSISTANT_ID}"
    aws qconnect get-assistant --assistant-id "$ASSISTANT_ID" --region "$AWS_REGION" | jq '.'
}

get_knowledge_base() {
    select_knowledge_base || return 1
    echo "Getting details for Knowledge Base ID: ${KNOWLEDGE_BASE_ID}"
    aws qconnect get-knowledge-base --knowledge-base-id "$KNOWLEDGE_BASE_ID" --region "$AWS_REGION" | jq '.'
}

get_content() {
    select_content || return 1
    echo "Getting details for Content ID: ${CONTENT_ID}"
    aws qconnect get-content --knowledge-base-id "$KNOWLEDGE_BASE_ID" --content-id "$CONTENT_ID" --region "$AWS_REGION" | jq '.'
}


# DELETE Commands
delete_assistant() {
    select_assistant || return 1
    echo -e "${C_YELLOW}You are about to delete assistant with ID: ${ASSISTANT_ID}${C_NC}"
    confirm_action && {
        aws qconnect delete-assistant --assistant-id "$ASSISTANT_ID" --region "$AWS_REGION"
        echo -e "${C_GREEN}Assistant ${ASSISTANT_ID} deleted. Clearing stored ID.${C_NC}"
        ASSISTANT_ID=""
    }
}

delete_knowledge_base() {
    select_knowledge_base || return 1
    echo -e "${C_YELLOW}You are about to delete Knowledge Base with ID: ${KNOWLEDGE_BASE_ID}${C_NC}"
    confirm_action && {
        aws qconnect delete-knowledge-base --knowledge-base-id "$KNOWLEDGE_BASE_ID" --region "$AWS_REGION"
        echo -e "${C_GREEN}Knowledge Base ${KNOWLEDGE_BASE_ID} deleted. Clearing stored ID.${C_NC}"
        KNOWLEDGE_BASE_ID=""
    }
}

# --- Menu Definitions ---
run_menu() {
    local menu_func=$1
    $menu_func
    press_enter_to_continue
}

# Main Menu
main_menu() {
    print_state
    echo "What action would you like to perform?"
    select choice in "List Resources" "Create Resource" "Get/Describe Resource" "Delete Resource" "Settings" "Exit"; do
        case $choice in
            "List Resources") run_menu list_menu; break ;;
            "Create Resource") run_menu create_menu; break ;;
            "Get/Describe Resource") run_menu get_menu; break ;;
            "Delete Resource") run_menu delete_menu; break ;;
            "Settings") run_menu settings_menu; break ;;
            "Exit") exit 0 ;;
            *) echo "Invalid option. Please try again.";;
        esac
    done
}

# List Menu
list_menu() {
    print_state
    echo "Which resource would you like to list?"
    select choice in "Assistants" "Knowledge Bases" "Content in a KB" "Quick Responses" "Back"; do
        case $choice in
            "Assistants") aws qconnect list-assistants --region "$AWS_REGION" | jq '.'; break ;;
            "Knowledge Bases") aws qconnect list-knowledge-bases --region "$AWS_REGION" | jq '.'; break ;;
            "Content in a KB")
                select_knowledge_base && aws qconnect list-contents --knowledge-base-id "$KNOWLEDGE_BASE_ID" --region "$AWS_REGION" | jq '.'
                break
                ;;
            "Quick Responses")
                select_knowledge_base && aws qconnect search-quick-responses --knowledge-base-id "$KNOWLEDGE_BASE_ID" --region "$AWS_REGION" | jq '.'
                break
                ;;
            "Back") break ;;
            *) echo "Invalid option.";;
        esac
    done
}

# Create Menu
create_menu() {
    print_state
    echo "Which resource would you like to create?"
    select choice in "Assistant" "Knowledge Base" "Back"; do
        case $choice in
            "Assistant") create_assistant; break ;;
            "Knowledge Base") create_knowledge_base; break ;;
            "Back") break ;;
            *) echo "Invalid option.";;
        esac
    done
}

# Get Menu
get_menu() {
    print_state
    echo "Which resource would you like to get/describe?"
    select choice in "Assistant" "Knowledge Base" "Content" "Back"; do
        case $choice in
            "Assistant") get_assistant; break ;;
            "Knowledge Base") get_knowledge_base; break ;;
            "Content") get_content; break ;;
            "Back") break ;;
            *) echo "Invalid option.";;
        esac
    done
}

# Delete Menu
delete_menu() {
    print_state
    echo -e "${C_RED}DANGER ZONE: Deletions are permanent.${C_NC}"
    echo "Which resource would you like to delete?"
    select choice in "Assistant" "Knowledge Base" "Back"; do
        case $choice in
            "Assistant") delete_assistant; break ;;
            "Knowledge Base") delete_knowledge_base; break ;;
            "Back") break ;;
            *) echo "Invalid option.";;
        esac
    done
}

# Settings Menu
settings_menu() {
    print_state
    echo "Configuration Options"
    select choice in "Change AWS Region" "Clear All Stored IDs" "Back"; do
        case $choice in
            "Change AWS Region")
                read -p "Enter new AWS Region [current: ${AWS_REGION}]: " new_region
                AWS_REGION=${new_region:-$AWS_REGION}
                echo -e "${C_GREEN}Region set to ${AWS_REGION}.${C_NC}"
                break
                ;;
            "Clear All Stored IDs")
                ASSISTANT_ID=""
                KNOWLEDGE_BASE_ID=""
                CONTENT_ID=""
                SESSION_ID=""
                echo -e "${C_GREEN}All stored IDs have been cleared.${C_NC}"
                break
                ;;
            "Back") break ;;
            *) echo "Invalid option.";;
        esac
    done
}


# --- Script Entrypoint ---
check_dependencies
while true; do
    main_menu
done
