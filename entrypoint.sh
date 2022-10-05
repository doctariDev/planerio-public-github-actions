#!/bin/bash
set -e


echo "you are running a custom planerio Github Action"

if [[ "${PLANERIO_SERVICE_NAME}" =~ skeleton ]]; then
    echo "Detected skeleton project - exiting gracefully"
    exit 0
fi

if [ -z "${PLANERIO_STATIC_ENVIRONMENT_NAME}" ]; then
    echo "Missing PLANERIO_STATIC_ENVIRONMENT_NAME"
    exit 1
fi

if [ -z "${BUILDNUMBER}" ]; then
    echo "Missing BUILDNUMBER"
    exit 1
fi

if [ -z "${BRANCHNAME}" ]; then
    echo "Missing BRANCHNAME"
    exit 1
fi

if [ -z "${COMMITHASH}" ]; then
    echo "Missing COMMITHASH"
    exit 1
fi

if [ -z "${DOCKERIMAGEHASH}" ]; then
    echo "Missing DOCKERIMAGEHASH"
    exit 1
fi




UNIQUEID=`cat /proc/sys/kernel/random/uuid`


echo "variables are cleared and set"

(
cat <<EOF
{
    "serviceName": "${PLANERIO_SERVICE_NAME}",
    "staticEnvironmentName": "${PLANERIO_STATIC_ENVIRONMENT_NAME}",

    "buildNumber": ${BUILDNUMBER},
    "branchName": "${BRANCHNAME}",
    "commitHash": "${COMMITHASH}",
    "dockerImageHash": "${DOCKERIMAGEHASH}",

    "uniqueId": "${UNIQUEID}"
}
EOF
) > /tmp/dpl_trigger_request.json

echo $(cat /tmp/dpl_trigger_request.json)

echo "start invoke lambda"

aws lambda invoke \
    --function-name 'planerio-microservice-deployment-triggerDeployment' \
    --cli-binary-format raw-in-base64-out --payload file://tmp/dpl_trigger_request.json \
    /tmp/dpl_trigger_response.json > /tmp/dpl_invokation_result.json
rc=$?
if [[ $rc -ne 0 ]] || [ ! -s /tmp/dpl_invokation_result.json ]; then
    exit $rc
fi
functionerror=`cat /tmp/dpl_invokation_result.json | jq -r '.FunctionError'`
if [ ! -z "${functionerror}" ] && [[ "${functionerror}" != "null" ]]; then
    cat /tmp/dpl_trigger_response.json | jq '.'
    exit 1
fi
deploymentname=`cat /tmp/dpl_trigger_response.json | jq -r '.uniqueDeploymentName'`
detailslink=`cat /tmp/dpl_trigger_response.json | jq -r '.detailsLink'`
echo Deployment started with ARN:
echo ${deploymentname}
echo .
progressid=0
while true; do
    sleep 5
        (
cat <<EOF
{
    "serviceName": "${PLANERIO_SERVICE_NAME}",
    "staticEnvironmentName": "${PLANERIO_STATIC_ENVIRONMENT_NAME}",
    "uniqueDeploymentName": "${deploymentname}",
    "previousProgressId": ${progressid}
}
EOF
        ) > /tmp/dpl_poll_request.json

    aws lambda invoke \
        --function-name 'planerio-microservice-deployment-pollDeploymentStatus' \
        --payload 'file:///tmp/dpl_poll_request.json' \
        /tmp/dpl_poll_status.json >/dev/null
    status=`cat /tmp/dpl_poll_status.json | jq -r '.status'`
    progressid=`cat /tmp/dpl_poll_status.json | jq -r '.maxProgressId'`
    cat /tmp/dpl_poll_status.json | jq -r '.progressSteps[]'
    if [[ "${status}" != "RUNNING" ]]; then
        break
    fi
done

echo .
echo Result status: ${status}
echo View details:
echo "${detailslink}"
echo .

if [[ "${status}" != "SUCCEEDED" ]]; then
    exit 255
fi


