#!/usr/bin/env bash
set -x

RANCHER_BASEURL=rancher-metadata.rancher.internal/latest

if [ -z "${SERVICE_GRAFANA_USERNAME}"]; then
  GRAFANA_AUTH=""
else
  GRAFANA_AUTH="${SERVICE_GRAFANA_USERNAME}:${SERVICE_GRAFANA_PASSWORD}@"
fi
GRAFANA_URL=http://${GRAFANA_AUTH}${SERVICE_GRAFANA_HOST}:${SERVICE_GRAFANA_PORT}

function checkGrafana {
    a="`curl ${GRAFANA_URL}/api/metrics &> /dev/null; echo $?`"
    while  [ $a -ne 0 ];
    do
        a="`curl ${GRAFANA_URL}/api/metrics &> /dev/null; echo $?`"
        sleep 1
    done
}

function retryHttp {
    httpWord=$1
    url=$2
    content=$3
    curlCommand="curl -X${httpWord} ${url} --compressed -H 'Content-Type: application/json;charset=UTF-8' --write-out %{http_code} --output /dev/null -d @${content}"
    status=$(eval $curlCommand)
    while  [ $status -ne 200 ] && [ $status -ne 409 ] ;
    do
        status=$(eval $curlCommand)
        sleep 1
    done
}

checkGrafana

mkdir /grafana

#get datasources
response=$(curl --write-out %{http_code} --silent --output /dev/null http://${RANCHER_BASEURL}/self/service/metadata/datasources)
if [ "$response" -eq 200 ]
then
    curl http://${RANCHER_BASEURL}/self/service/metadata/datasources > /grafana/datasources.json
    mkdir -p /grafana/datasources
    jq -rc '.[]' /grafana/datasources.json | while IFS='' read objectConfig ; do
      name=$(echo $objectConfig | jq -r .name)
      config=$(echo $objectConfig | jq .value)
      if [ "$name" = "null" ] && [ "$config" = "null" ]; then
        echo "datasource name or config is null, ignoring this entry..."
      else
        echo Posting datasource config $name
        echo $config > /grafana/datasources/$name.json
        retryHttp POST ${GRAFANA_URL}/api/datasources/ /grafana/datasources/$name.json
      fi
    done
fi

#get dashboards
response=$(curl --write-out %{http_code} --silent --output /dev/null http://${RANCHER_BASEURL}/self/service/metadata/dashboards)
if [ "$response" -eq 200 ]
then
    curl http://${RANCHER_BASEURL}/self/service/metadata/dashboards > /grafana/dashboards.json
    mkdir -p /grafana/dashboards
    jq -rc '.[]' /grafana/dashboards.json | while IFS='' read objectConfig ; do
      name=$(echo $objectConfig | jq -r .name)
      config=$(echo $objectConfig | jq .value)
      if [ "$name" = "null" ] && [ "$config" = "null" ]; then
        echo "dashboards name or config is null, ignoring this entry..."
      else
        echo Posting dashboards config $name
        echo $config > /grafana/dashboards/$name.json
        retryHttp POST ${GRAFANA_URL}/api/dashboards/db /grafana/dashboards/$name.json
      fi
    done
fi

#get notifications
response=$(curl --write-out %{http_code} --silent --output /dev/null http://${RANCHER_BASEURL}/self/service/metadata/notifications)
if [ "$response" -eq 200 ]
then
    curl http://${RANCHER_BASEURL}/self/service/metadata/notifications > /grafana/notifications.json
    mkdir -p /grafana/notifications
    jq -rc '.[]' /grafana/notifications.json | while IFS='' read objectConfig ; do
      name=$(echo $objectConfig | jq -r .name)
      config=$(echo $objectConfig | jq .value)
      if [ "$name" = "null" ] && [ "$config" = "null" ]; then
        echo "notifications name or config is null, ignoring this entry..."
      else
        echo Posting notifications config $name
        echo $config > /grafana/notifications/$name.json
        retryHttp POST ${GRAFANA_URL}/api/alert-notifications /grafana/notifications/$name.json
      fi
    done
fi
