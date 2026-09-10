# Floci Setup org and accounts and ou

```bash
aws organizations create-organization \
  --feature-set ALL \
  --profile floci
```

## get root id

```bash
ROOT_ID=$(aws organizations list-roots \
  --query 'Roots[0].Id' \
  --output text \
  --profile floci)

echo $ROOT_ID
```
## create workload ou
```bash
aws organizations create-organizational-unit \
  --parent-id $ROOT_ID \
  --name Workloads \
  --profile floci
```

```bash
WORKLOADS_OU=$(aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --query "OrganizationalUnits[?Name=='Workloads'].Id" \
  --output text \
  --profile floci)

echo $WORKLOADS_OU
```

## create prod and nonprod ou
```bash
aws organizations create-organizational-unit \
  --parent-id $WORKLOADS_OU \
  --name Prod \
  --profile floci

aws organizations create-organizational-unit \
  --parent-id $WORKLOADS_OU \
  --name NonProd \
  --profile floci  
```

## capture ids

```bash
PROD_OU=$(aws organizations list-organizational-units-for-parent \
  --parent-id $WORKLOADS_OU \
  --query "OrganizationalUnits[?Name=='Prod'].Id" \
  --output text \
  --profile floci)

NONPROD_OU=$(aws organizations list-organizational-units-for-parent \
  --parent-id $WORKLOADS_OU \
  --query "OrganizationalUnits[?Name=='NonProd'].Id" \
  --output text \
  --profile floci)

echo $PROD_OU
echo $NONPROD_OU
```

## creat accounts

```bash
aws organizations create-account \
  --email prod@example.com \
  --account-name prod \
  --profile floci

aws organizations create-account \
  --email nonprod@example.com \
  --account-name nonprod \
  --profile floci


PROD_ACCT=$(aws organizations list-accounts \
  --query "Accounts[?Name=='prod'].Id" \
  --output text \
  --profile floci)

NONPROD_ACCT=$(aws organizations list-accounts \
  --query "Accounts[?Name=='nonprod'].Id" \
  --output text \
  --profile floci)

echo $NONPROD_ACCT
echo $PROD_ACCT

```


## move accoutns to ou

```bash
aws organizations move-account \
  --account-id $PROD_ACCT \
  --source-parent-id $ROOT_ID \
  --destination-parent-id $PROD_OU \
  --profile floci
aws organizations move-account \
  --account-id $NONPROD_ACCT \
  --source-parent-id $ROOT_ID \
  --destination-parent-id $NONPROD_OU \
  --profile floci

```

## verify structure

```bash

aws organizations list-organizational-units-for-parent \
  --parent-id $ROOT_ID \
  --profile floci
aws organizations list-accounts-for-parent \
  --parent-id $PROD_OU \
  --profile floci
aws organizations list-accounts-for-parent \
  --parent-id $NONPROD_OU \
  --profile floci
```

## final hierarchy

Root
└── Workloads
    ├── Prod
    │   └── prod
    └── NonProd
        └── nonprod



## setup.sh

```bash
#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE="${AWS_PROFILE:-floci}"

WORKLOAD_OU_NAME="workload-ou"
PROD_OU_NAME="prod-ou"
NONPROD_OU_NAME="nonprod-ou"

PROD_ACCOUNT_NAME="prod"
PROD_ACCOUNT_EMAIL="prod@example.com"

NONPROD_ACCOUNT_NAME="nonprod"
NONPROD_ACCOUNT_EMAIL="nonprod@example.com"

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

aws_cli() {
    aws "$@" --profile "${PROFILE}" --no-cli-pager
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

get_account_id() {
    local account_name="$1"

    aws_cli organizations list-accounts \
        --query "Accounts[?Name=='${account_name}'].Id | [0]" \
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
    local request_id

    account_id="$(get_account_id "${account_name}")"

    if [[ -n "${account_id}" && "${account_id}" != "None" ]]; then
        log "Account already exists: ${account_name} (${account_id})"
    else
        log "Creating account: ${account_name}"

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
    fi

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
        fail "Unable to determine current parent for account ${account_name}"

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

    log "Moved account ${account_name} successfully"
}

verify_prerequisites() {
    command -v aws >/dev/null 2>&1 ||
        fail "AWS CLI is not installed or is not in PATH"

    aws_cli sts get-caller-identity >/dev/null 2>&1 ||
        fail "Unable to access Floci using profile ${PROFILE}"
}

main() {
    log "Using AWS CLI profile: ${PROFILE}"

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

    WORKLOAD_OU_ID="$(ensure_ou "${ROOT_ID}" "${WORKLOAD_OU_NAME}")"
    PROD_OU_ID="$(ensure_ou "${WORKLOAD_OU_ID}" "${PROD_OU_NAME}")"
    NONPROD_OU_ID="$(ensure_ou "${WORKLOAD_OU_ID}" "${NONPROD_OU_NAME}")"

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

    log "Organization setup completed"

    cat <<EOF

Organization hierarchy:

${ROOT_ID}
└── ${WORKLOAD_OU_NAME} (${WORKLOAD_OU_ID})
    ├── ${PROD_OU_NAME} (${PROD_OU_ID})
    │   └── ${PROD_ACCOUNT_NAME} (${PROD_ACCOUNT_ID})
    └── ${NONPROD_OU_NAME} (${NONPROD_OU_ID})
        └── ${NONPROD_ACCOUNT_NAME} (${NONPROD_ACCOUNT_ID})

EOF

    log "Verifying Prod account placement"

    aws_cli organizations list-accounts-for-parent \
        --parent-id "${PROD_OU_ID}" \
        --query 'Accounts[].{Name:Name,Id:Id,Email:Email,Status:Status}' \
        --output table

    log "Verifying NonProd account placement"

    aws_cli organizations list-accounts-for-parent \
        --parent-id "${NONPROD_OU_ID}" \
        --query 'Accounts[].{Name:Name,Id:Id,Email:Email,Status:Status}' \
        --output table
}

main "$@"
```
```bash
chmod +x setup-org.sh
./setup-org.sh
```

