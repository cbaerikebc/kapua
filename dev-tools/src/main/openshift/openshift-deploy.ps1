###############################################################################
#
# BCGOV - OpenShift S2I deployment of Eclipse Kapua
# 
# Note: This script assumes that "oc login" has been run
# 
###############################################################################

Param(
  [string]$ProjectName = $(Read-Host "Project name"),
  [string]$DBUrl =  $(Read-Host "DB Init file URL"),
  [bool]$CleanProject = $false
)

$DockerSource = "hekonsek"
# $ElasticSearchMemory= "512M"
$SqlPod = ""

oc project $ProjectName

if ($CleanProject){
  # Clean out the project to make room for a new deploy
  oc delete all --all
  sleep 30
}

# Deploy Database
echo "Deploying Database"
oc new-app $DockerSource/kapua-sql --name=sql -n $ProjectName
# TODO: use persistent storage
echo "Initializing Database"
While ("" -eq $SqlPod){
  # Wait until the pod is created and running
  echo "Waiting for pod to start"
  sleep 10
  $SqlPod = oc get pods | Select-String -Pattern "sql-[^ ]*.*Running" -List | %{$_.Matches} | %{$_.Value}
}
sleep 30
$SqlPod = oc get pods | Select-String -Pattern "sql-[^ ]*" -List | %{$_.Matches} | %{$_.Value}
echo "Using SQL pod: $SqlPod"
oc exec $SqlPod -i -- curl $DBUrl -o /tmp/db.sql
oc exec $SqlPod -i -- sh -c 'java -cp /opt/h2/bin/h2*.jar org.h2.tools.RunScript -url jdbc:h2:tcp://localhost:3306/kapuadb -user kapua -password kapua -script /tmp/db.sql'

# Deploy Broker
echo "Deploying Kapua Broker"
oc new-app $DockerSource/kapua-broker:latest -name=kapua-broker -n $ProjectName

# Deploy API
echo "Deploying Kapua API"
oc new-app $DockerSource/kapua-api:latest -n $ProjectName

# Deploy Console
echo "Deploying Kapua Console"
oc new-app $DockerSource/kapua-console:latest -n $ProjectName -e COMMONS_DB_SCHEMA=' '
oc create route edge kapua-console --service=kapua-console --insecure-policy='Redirect'

# Deploy Elastic Search
# echo "Deploying Elastic Search"
# oc new-app -e ES_JAVA_OPTS="-Xms$ElasticSearchMemory -Xmx$ElasticSearchMemory" elasticsearch:2.4 -n $ProjectName

