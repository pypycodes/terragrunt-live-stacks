#!/usr/bin/env bash



### USAGE:
# chmod +x setup-floci-org.sh
# ./setup-floci-org.sh \
#   --profile floci \
#   --workload-ou workload-ou \
#   --prod-ou prod-ou \
#   --nonprod-ou nonprod-ou \
#   --prod-account-name prod \
#   --prod-email prod@local.test \
#   --nonprod-account-name nonprod \
#   --nonprod-email nonprod@local.test
export AWS_PROFILE="floci"
export WORKLOAD_OU_NAME="workload-ou"
export PROD_OU_NAME="prod-ou"
export NONPROD_OU_NAME="nonprod-ou"
export PROD_ACCOUNT_NAME="prod"
export PROD_ACCOUNT_EMAIL="prod@local.test"
export NONPROD_ACCOUNT_NAME="nonprod"
export NONPROD_ACCOUNT_EMAIL="nonprod@local.test"
# ./setup-floci-org.sh

set -Eeuo pipefail

# Defaults. Environment variables can override these values.
PROFILE="${AWS_PROFILE:-floci}"

WORKLOAD_OU_NAME="${WORKLOAD_OU_NAME:-workload-ou}"
PROD_OU_NAME="${PROD_OU_NAME:-prod-ou}"
NONPROD_OU_NAME="${NONPROD_OU_NAME:-nonprod-ou}"

PROD_ACCOUNT_NAME="${PROD_ACCOUNT_NAME:-prod}"
PROD_ACCOUNT_EMAIL="${PROD_ACCOUNT_EMAIL:-prod@example.com}"

NONPROD_ACCOUNT_NAME="${NONPROD_ACCOUNT_NAME:-nonprod}"
NONPROD_ACCOUNT_EMAIL="${NONPROD_ACCOUNT_EMAIL:-nonprod@example.com}"

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  $0 [options]

Options:
  --profile NAME              AWS CLI profile
  --workload-ou NAME          Parent workload OU name
  --prod-ou NAME              Production OU name
  --nonprod-ou NAME           Non-production OU name
  --prod-account-name NAME    Production account name
  --prod-email EMAIL          Production account email
  --nonprod-account-name NAME Non-production account name
  --nonprod-email EMAIL       Non-production account email
  -h, --help                  Show this help

Environment variables:
  AWS_PROFILE
  WORKLOAD_OU_NAME
  PROD_OU_NAME
  NONPROD_OU_NAME
  PROD_ACCOUNT_NAME
  PROD_ACCOUNT_EMAIL
  NONPROD_ACCOUNT_NAME
  NONPROD_ACCOUNT_EMAIL

Example:
  $0 \\
    --profile floci \\
    --workload-ou workload-ou \\
    --prod-ou prod-ou \\
    --nonprod-ou nonprod-ou \\
    --prod-account-name prod \\
    --prod-email prod@local.test \\
    --nonprod-account-name nonprod \\
    --nonprod-email nonprod@local.test
EOF
}

require_value() {
    local option="$1"
    local value="${2:-}"

    [[ -n "${value}" ]] ||
        fail "Missing value for ${option}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            require_value "$1" "${2:-}"
            PROFILE="$2"
            shift 2
            ;;
        --workload-ou)
            require_value "$1" "${2:-}"
            WORKLOAD_OU_NAME="$2"
            shift 2
            ;;
        --prod-ou)
            require_value "$1" "${2:-}"
            PROD_OU_NAME="$2"
            shift 2
            ;;
        --nonprod-ou)
            require_value "$1" "${2:-}"
            NONPROD_OU_NAME="$2"
            shift 2
            ;;
        --prod-account-name)
            require_value "$1" "${2:-}"
            PROD_ACCOUNT_NAME="$2"
            shift 2
            ;;
        --prod-email)
            require_value "$1" "${2:-}"
            PROD_ACCOUNT_EMAIL="$2"
            shift 2
            ;;
        --nonprod-account-name)
            require_value "$1" "${2:-}"
            NONPROD_ACCOUNT_NAME="$2"
            shift 2
            ;;
        --nonprod-email)
            require_value "$1" "${2:-}"
            NONPROD_ACCOUNT_EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1. Use --help for usage."
            ;;
    esac
done

aws_cli() {
    aws "$@" \
        --profile "${PROFILE}" \
        --no-cli-pager
}

organization_exists() {
    aws_cli organizations describe-organization >/dev/null 2>&1
}

get_ou_id() {
    local parent_id="$1"
    local ou_name="$2"

    aws_cli organizations list-organizational-units-for-parent \
        --parent-id "${parent_id}" \
        --query "OrganizationalUnits[?Name=='${ou_name}'].Id | [0]" \
        --output text
}

ensure_ou() {
    local parent_id="$1"
    local ou_name="$2"
    local ou_id

    ou_id="$(get_ou_id "${parent_id}" "${ou_name}")"

    if [[ -n "${ou_id}" && "${ou_id}" != "None" ]]; then
        log "OU already exists: ${ou_name} (${ou_id})"
    else
        log "Creating OU: ${ou_name}"

        ou_id="$(
            aws_cli organizations create-organizational-unit \
                --parent-id "${parent_id}" \
                --name "${ou_name}" \
                --query 'OrganizationalUnit.Id' \
                --output text
        )"

        [[ -n "${ou_id}" && "${ou_id}" != "None" ]] ||
            fail "Unable to create OU: ${ou_name}"

        log "Created OU: ${ou_name} (${ou_id})"
    fi

    printf '%s\n' "${ou_id}"
}

get_account_id_by_name() {
    local account_name="$1"

    aws_cli organizations list-accounts \
        --query "Accounts[?Name=='${account_name}'].Id | [0]" \
        --output text
}

get_account_id_by_email() {
    local account_email="$1"

    aws_cli organizations list-accounts \
        --query "Accounts[?Email=='${account_email}'].Id | [0]" \
        --output text
}

wait_for_account_creation() {
    local request_id="$1"
    local state
    local account_id
    local failure_reason
    local attempt

    for attempt in $(seq 1 30); do
        state="$(
            aws_cli organizations describe-create-account-status \
                --create-account-request-id "${request_id}" \
                --query 'CreateAccountStatus.State' \
                --output text
        )"

        case "${state}" in
            SUCCEEDED)
                account_id="$(
                    aws_cli organizations describe-create-account-status \
                        --create-account-request-id "${request_id}" \
                        --query 'CreateAccountStatus.AccountId' \
                        --output text
                )"

                printf '%s\n' "${account_id}"
                return 0
                ;;
            FAILED)
                failure_reason="$(
                    aws_cli organizations describe-create-account-status \
                        --create-account-request-id "${request_id}" \
                        --query 'CreateAccountStatus.FailureReason' \
                        --output text
                )"

                fail "Account creation failed: ${failure_reason}"
                ;;
            IN_PROGRESS)
                sleep 1
                ;;
            *)
                fail "Unexpected account creation state: ${state}"
                ;;
        esac
    done

    fail "Account creation did not complete after 30 checks"
}

ensure_account() {
    local account_name="$1"
    local account_email="$2"
    local account_id
    local email_account_id
    local request_id

    account_id="$(get_account_id_by_name "${account_name}")"

    if [[ -n "${account_id}" && "${account_id}" != "None" ]]; then
        log "Account already exists: ${account_name} (${account_id})"
        printf '%s\n' "${account_id}"
        return 0
    fi

    email_account_id="$(get_account_id_by_email "${account_email}")"

    if [[ -n "${email_account_id}" && "${email_account_id}" != "None" ]]; then
        fail "Email ${account_email} is already associated with account ${email_account_id}"
    fi

    log "Creating account: ${account_name} using ${account_email}"

    request_id="$(
        aws_cli organizations create-account \
            --email "${account_email}" \
            --account-name "${account_name}" \
            --query 'CreateAccountStatus.Id' \
            --output text
    )"

    [[ -n "${request_id}" && "${request_id}" != "None" ]] ||
        fail "Unable to start account creation for ${account_name}"

    log "Account creation request: ${request_id}"

    account_id="$(wait_for_account_creation "${request_id}")"

    [[ -n "${account_id}" && "${account_id}" != "None" ]] ||
        fail "Unable to determine account ID for ${account_name}"

    log "Created account: ${account_name} (${account_id})"

    printf '%s\n' "${account_id}"
}

get_account_parent_id() {
    local account_id="$1"

    aws_cli organizations list-parents \
        --child-id "${account_id}" \
        --query 'Parents[0].Id' \
        --output text
}

ensure_account_parent() {
    local account_id="$1"
    local destination_parent_id="$2"
    local account_name="$3"
    local current_parent_id

    current_parent_id="$(get_account_parent_id "${account_id}")"

    [[ -n "${current_parent_id}" && "${current_parent_id}" != "None" ]] ||
        fail "Unable to determine parent for account ${account_name}"

    if [[ "${current_parent_id}" == "${destination_parent_id}" ]]; then
        log "Account ${account_name} is already in ${destination_parent_id}"
        return 0
    fi

    log "Moving ${account_name} from ${current_parent_id} to ${destination_parent_id}"

    aws_cli organizations move-account \
        --account-id "${account_id}" \
        --source-parent-id "${current_parent_id}" \
        --destination-parent-id "${destination_parent_id}" \
        >/dev/null

    log "Moved account ${account_name}"
}

verify_prerequisites() {
    command -v aws >/dev/null 2>&1 ||
        fail "AWS CLI is not installed or is not available in PATH"

    aws_cli sts get-caller-identity >/dev/null 2>&1 ||
        fail "Unable to access Floci using profile ${PROFILE}"
}

print_configuration() {
    cat <<EOF

Configuration:
  AWS profile             : ${PROFILE}
  Workload OU             : ${WORKLOAD_OU_NAME}
  Production OU           : ${PROD_OU_NAME}
  Non-production OU       : ${NONPROD_OU_NAME}
  Production account      : ${PROD_ACCOUNT_NAME}
  Production email        : ${PROD_ACCOUNT_EMAIL}
  Non-production account  : ${NONPROD_ACCOUNT_NAME}
  Non-production email    : ${NONPROD_ACCOUNT_EMAIL}

EOF
}

update_floci_credentials() {
    echo "Updating AWS credential profiles..."

    aws configure set aws_access_key_id "${PROD_ACCOUNT_ID}" \
        --profile floci-prod

    aws configure set aws_secret_access_key "test" \
        --profile floci-prod

    aws configure set aws_access_key_id "${NONPROD_ACCOUNT_ID}" \
        --profile floci-nonprod

    aws configure set aws_secret_access_key "test" \
        --profile floci-nonprod

    echo "Updated profiles:"
    echo "  floci-prod     -> ${PROD_ACCOUNT_ID}"
    echo "  floci-nonprod  -> ${NONPROD_ACCOUNT_ID}"
}


main() {
    print_configuration
    verify_prerequisites

    if organization_exists; then
        log "AWS Organization already exists"
    else
        log "Creating AWS Organization"

        aws_cli organizations create-organization \
            --feature-set ALL \
            >/dev/null

        log "AWS Organization created"
    fi

    ROOT_ID="$(
        aws_cli organizations list-roots \
            --query 'Roots[0].Id' \
            --output text
    )"

    [[ -n "${ROOT_ID}" && "${ROOT_ID}" != "None" ]] ||
        fail "Unable to determine organization root ID"

    log "Organization root: ${ROOT_ID}"

    WORKLOAD_OU_ID="$(
        ensure_ou "${ROOT_ID}" "${WORKLOAD_OU_NAME}"
    )"

    PROD_OU_ID="$(
        ensure_ou "${WORKLOAD_OU_ID}" "${PROD_OU_NAME}"
    )"

    NONPROD_OU_ID="$(
        ensure_ou "${WORKLOAD_OU_ID}" "${NONPROD_OU_NAME}"
    )"

    PROD_ACCOUNT_ID="$(
        ensure_account "${PROD_ACCOUNT_NAME}" "${PROD_ACCOUNT_EMAIL}"
    )"

    NONPROD_ACCOUNT_ID="$(
        ensure_account "${NONPROD_ACCOUNT_NAME}" "${NONPROD_ACCOUNT_EMAIL}"
    )"

    ensure_account_parent \
        "${PROD_ACCOUNT_ID}" \
        "${PROD_OU_ID}" \
        "${PROD_ACCOUNT_NAME}"

    ensure_account_parent \
        "${NONPROD_ACCOUNT_ID}" \
        "${NONPROD_OU_ID}" \
        "${NONPROD_ACCOUNT_NAME}"

    cat <<EOF

Organization hierarchy:

${ROOT_ID}
└── ${WORKLOAD_OU_NAME} (${WORKLOAD_OU_ID})
    ├── ${PROD_OU_NAME} (${PROD_OU_ID})
    │   └── ${PROD_ACCOUNT_NAME} (${PROD_ACCOUNT_ID})
    └── ${NONPROD_OU_NAME} (${NONPROD_OU_ID})
        └── ${NONPROD_ACCOUNT_NAME} (${NONPROD_ACCOUNT_ID})

EOF

    log "Production account placement"

    aws_cli organizations list-accounts-for-parent \
        --parent-id "${PROD_OU_ID}" \
        --query 'Accounts[].{Name:Name,Id:Id,Email:Email,Status:Status}' \
        --output table

    log "Non-production account placement"

    aws_cli organizations list-accounts-for-parent \
        --parent-id "${NONPROD_OU_ID}" \
        --query 'Accounts[].{Name:Name,Id:Id,Email:Email,Status:Status}' \
        --output table

update_floci_credentials

echo
echo "Validating profiles..."

AWS_PROFILE=floci-prod aws sts get-caller-identity

AWS_PROFILE=floci-nonprod aws sts get-caller-identity


cat > /home/pg/github/pluralsight/terragrunt-live-stacks/floci-accounts.env <<EOF
export EX_PROD_ACCOUNT_ID="${PROD_ACCOUNT_ID}"
export EX_NON_PROD_ACCOUNT_ID="${NONPROD_ACCOUNT_ID}"
export EX_PROD_OU_ID="${PROD_OU_ID}"
export EX_NON_PROD_OU_ID="${NONPROD_OU_ID}"
export EX_WORKLOAD_OU_ID="${WORKLOAD_OU_ID}"
export EX_PROD_ACCOUNT_NAME="${PROD_ACCOUNT_NAME}"
export EX_NON_PROD_ACCOUNT_NAME="${NONPROD_ACCOUNT_NAME}"
export EX_PROD_PROFILE="floci-prod"
export EX_NON_PROD_PROFILE="floci-nonprod"
EOF
log "Organization setup completed successfully"
log "Generated: /home/pg/github/pluralsight/terragrunt-live-stacks/floci-accounts.env"
echo "Run:below-->"
echo "source /home/pg/github/pluralsight/terragrunt-live-stacks/floci-accounts.env "

}

main "$@"

