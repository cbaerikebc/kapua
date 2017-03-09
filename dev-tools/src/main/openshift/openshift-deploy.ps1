###############################################################################
#
# BCGOV - OpenShift deployment of Eclipse Kapua
# 
# Note: This script assumes that "oc login" has been run.
#       It also requires 2 persistent volume claims named:
#       1) kapua-sql-* for the H2 database
#       2) kapua-broker-* for the ActiveMQ database
# 
###############################################################################

Param(
  [string]$ProjectName = $(Read-Host "Project name"),
  [string]$DockerSource = "ctron",
  [bool]$CleanProject = $false
)

# $ElasticSearchMemory= "512M"

oc project $ProjectName

if ($CleanProject){
  # Clean out the project to make room for a new deploy
  oc delete route kapua-broker -n $ProjectName
  oc delete route kapua-console -n $ProjectName
  oc delete route kapua-api -n $ProjectName
  oc delete dc kapua-console -n $ProjectName
  oc delete dc kapua-api -n $ProjectName
  oc delete dc kapua-broker -n $ProjectName
  oc delete dc sql -n $ProjectName
  oc delete service kapua-console -n $ProjectName
  oc delete service kapua-api -n $ProjectName
  oc delete service kapua-broker -n $ProjectName
  oc delete service sql -n $ProjectName
  oc delete is kapua-console -n $ProjectName
  oc delete is kapua-api -n $ProjectName
  oc delete is kapua-broker -n $ProjectName
  oc delete is sql -n $ProjectName
  # Wait until all pods are gone
  sleep 60
}

# Deploy Database
echo "Deploying Database"
oc new-app $DockerSource/kapua-sql:latest --name=sql -n $ProjectName
oc set probe dc/sql --readiness --initial-delay-seconds=15 --open-tcp=3306
$SqlPod = ""
While ("" -eq $SqlPod){
  # Wait until the pod is created and running
  echo "Waiting for pod to start."
  sleep 15
  $SqlPod = oc get pods | Select-String -Pattern "sql-[^ ]*.*1/1.*Running" -List | %{$_.Matches} | %{$_.Value}
}
echo "Waiting for the pod to deploy the database engine."
sleep 30
$SqlPod = oc get pods | Select-String -Pattern "sql-[^ ]*" -List | %{$_.Matches} | %{$_.Value}
echo "Adding persistent volumes. Using SQL pod: $SqlPod"
$Pvc = oc get pvc | Select-String -Pattern "kapua-sql-[^ ]*" -List | %{$_.Matches} | %{$_.Value}
oc volume dc/sql --remove --name=sql-volume-1
oc volume dc/sql --add --name=sql-pv-1 --type=persistentVolumeClaim --claim-name=$Pvc --mount-path=/opt/h2-data
echo "Waiting for the pod to redeploy after adding persistent volumes."
sleep 30

# Deploy Broker
echo "Deploying Kapua Broker"
oc new-app $DockerSource/kapua-broker:latest --name=kapua-broker -n $ProjectName '-eACTIVEMQ_OPTS=-Dcommons.db.connection.host=$SQL_SERVICE_HOST -Dcommons.db.connection.port=$SQL_SERVICE_PORT_3306_TCP'
sleep 30
$BrokerPod = oc get pods | Select-String -Pattern "kapua-broker-[^ ]*" -List | %{$_.Matches} | %{$_.Value}
echo "Adding persistent volumes. Using Broker pod: $BrokerPod"
$Pvc = oc get pvc | Select-String -Pattern "kapua-broker-[^ ]*" -List | %{$_.Matches} | %{$_.Value}
oc volume dc/kapua-broker --remove --name=kapua-broker-volume-1
oc volume dc/kapua-broker --add --name=kapua-broker-volume-1 --type=persistentVolumeClaim --claim-name=$Pvc --mount-path=/maven/data
oc create route edge kapua-broker --service=kapua-broker --port=61614 --insecure-policy='Redirect'
oc set probe dc/kapua-broker -n $ProjectName --readiness --initial-delay-seconds=120 --open-tcp=1883

# Deploy Console
echo "Deploying Kapua Console"
oc new-app $DockerSource/kapua-console:latest -n $ProjectName '-eCATALINA_OPTS=-Dcommons.db.connection.host=$SQL_SERVICE_HOST -Dcommons.db.connection.port=$SQL_SERVICE_PORT_3306_TCP -Dbroker.host=$KAPUA_BROKER_SERVICE_HOST'
oc create route edge kapua-console --path=/console --service=kapua-console --insecure-policy='Redirect'
oc set probe dc/kapua-console -n $ProjectName --readiness --liveness --initial-delay-seconds=120 --request-timeout=10 --get-url=http://:8080/console

# Deploy API
echo "Deploying Kapua API"
oc new-app $DockerSource/kapua-api:latest -n $ProjectName '-eCATALINA_OPTS=-Dcommons.db.connection.host=$SQL_SERVICE_HOST -Dcommons.db.connection.port=$SQL_SERVICE_PORT_3306_TCP -Dbroker.host=$KAPUA_BROKER_SERVICE_HOST'
oc create route edge kapua-api --path=/api --service=kapua-api --insecure-policy='Redirect'
oc set probe dc/kapua-api -n $ProjectName --readiness --liveness --initial-delay-seconds=120 --request-timeout=10 --get-url=http://:8080/api

# Deploy Elastic Search
# echo "Deploying Elastic Search"
# oc new-app -e ES_JAVA_OPTS="-Xms$ElasticSearchMemory -Xmx$ElasticSearchMemory" elasticsearch:2.4 -n $ProjectName
