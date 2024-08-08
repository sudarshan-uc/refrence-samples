#!/bin/bash

ORGANIZATION_ID=
DEPLOYMENT_ID=
ASTRO_API_TOKEN=
AIRFLOW_PROJECT_PATH=
DAG_FOLDER="dags"

# Determine if only DAG files have changes
files=$(git diff --name-only $(git rev-parse HEAD~1) -- .)
dags_only=1
for file in $files;do
if [[ $file != "$DAG_FOLDER"* ]];then
    echo "$file is not a dag, triggering a full image build"
    dags_only=0
    break
fi
done


# If only DAGs changed deploy only the DAGs in your 'dags' folder to your Deployment
if [ $dags_only == 1 ]
then
	# Initializing Deploy
	echo -e "Initiating Deploy Process for deployment $DEPLOYMENT_ID\n"
	CREATE_DEPLOY=$(curl --location --request POST "https://api.astronomer.io/platform/v1beta1/organizations/$ORGANIZATION_ID/deployments/$DEPLOYMENT_ID/deploys" \
	--header "X-Astro-Client-Identifier: script" \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $ASTRO_API_TOKEN" \
	--data '{
	"type": "DAG_ONLY"
	}' | jq '.')

	DEPLOY_ID=$(echo $CREATE_DEPLOY | jq -r '.id')
	# Upload dags tar file
	DAGS_UPLOAD_URL=$(echo $CREATE_DEPLOY | jq -r '.dagsUploadUrl')
	echo -e "\nCreating a dags tar file from $AIRFLOW_PROJECT_PATH/dags and stored in $AIRFLOW_PROJECT_PATH/dags.tar\n"
	cd $AIRFLOW_PROJECT_PATH
	tar -cvf "$AIRFLOW_PROJECT_PATH/dags.tar" "dags"
	echo -e "\nUploading tar file $AIRFLOW_PROJECT_PATH/dags.tar\n"
	VERSION_ID=$(curl -i --request PUT $DAGS_UPLOAD_URL \
	--header 'x-ms-blob-type: BlockBlob' \
	--header 'Content-Type: application/x-tar' \
	--upload-file "$AIRFLOW_PROJECT_PATH/dags.tar" | grep x-ms-version-id | awk -F': ' '{print $2}')
	
	VERSION_ID=$(echo $VERSION_ID | sed 's/\r//g') # Remove unexpected carriage return characters
	echo -e "\nTar file uploaded with version: $VERSION_ID\n"
	
	# Finalizing Deploy
	FINALIZE_DEPLOY=$(curl --location --request POST "https://api.astronomer.io/platform/v1beta1/organizations/$ORGANIZATION_ID/deployments/$DEPLOYMENT_ID/deploys/$DEPLOY_ID/finalize" \
	--header "X-Astro-Client-Identifier: script" \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $ASTRO_API_TOKEN" \
	--data '{"dagTarballVersion": "'$VERSION_ID'"}')
	
	ID=$(echo $FINALIZE_DEPLOY | jq -r '.id')
	echo $ID
	if [[ "$ID" != null ]]; then
	        echo -e "\nDeploy is Finalized. DAG changes for deployment $DEPLOYMENT_ID should be live in a few minutes"
	        echo "Deployed DAG Tarball Version: $VERSION_ID"
	else
	        MESSAGE=$(echo $FINALIZE_DEPLOY | jq -r '.message')
	        if  [[ "$MESSAGE" != null ]]; then
	                echo $MESSAGE
	        else
	                echo "Something went wrong. Reach out to astronomer support for assistance"
	        fi
	fi
	
	# Cleanup
	echo -e "\nCleaning up the created tar file from $AIRFLOW_PROJECT_PATH/dags.tar"
	rm -rf "$AIRFLOW_PROJECT_PATH/dags.tar" 
fi
# If any other files changed build your Astro project into a Docker image, push the image to your Deployment, and then push and DAG changes
if [ $dags_only == 0 ]
then
	# Initializing Deploy
	echo -e "Initiating Deploy Process for deployment $DEPLOYMENT_ID\n"
	CREATE_DEPLOY=$(curl --location --request POST "https://api.astronomer.io/platform/v1beta1/organizations/$ORGANIZATION_ID/deployments/$DEPLOYMENT_ID/deploys" \
	--header "X-Astro-Client-Identifier: script" \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $ASTRO_API_TOKEN" \
	--data '{
	"type": "IMAGE_AND_DAG"
	}' | jq '.')

	DEPLOY_ID=$(echo $CREATE_DEPLOY | jq -r '.id')
   # Build and Push Docker Image
	REPOSITORY=$(echo $CREATE_DEPLOY | jq -r '.imageRepository')
	TAG=$(echo $CREATE_DEPLOY | jq -r '.imageTag')
	#podman login images.astronomer.cloud -u cli -p $ASTRO_API_TOKEN
    buildah login -u "cli" -p "$ASTRO_API_TOKEN" images.astronomer.cloud
	echo -e "\nBuilding Docker image $REPOSITORY:$TAG for $DEPLOYMENT_ID from $AIRFLOW_PROJECT_PATH"
	#podman build -t $REPOSITORY:$TAG --platform=linux/amd64 $AIRFLOW_PROJECT_PATH
    buildah --storage-driver=vfs bud --format=docker -t $REPOSITORY:$TAG --platform=linux/amd64 $AIRFLOW_PROJECT_PATH
	echo -e "\nPushing Docker image $REPOSITORY:$TAG to $DEPLOYMENT_ID"
    #docker push $REPOSITORY:$TAG
	buildah --storage-driver=vfs push $REPOSITORY:$TAG
	
	# Upload dags tar file
	DAGS_UPLOAD_URL=$(echo $CREATE_DEPLOY | jq -r '.dagsUploadUrl')
	echo -e "\nCreating a dags tar file from $AIRFLOW_PROJECT_PATH/dags and stored in $AIRFLOW_PROJECT_PATH/dags.tar\n"
	cd $AIRFLOW_PROJECT_PATH
	tar -cvf "$AIRFLOW_PROJECT_PATH/dags.tar" "dags"
	echo -e "\nUploading tar file $AIRFLOW_PROJECT_PATH/dags.tar\n"
	VERSION_ID=$(curl -i --request PUT $DAGS_UPLOAD_URL \
	--header 'x-ms-blob-type: BlockBlob' \
	--header 'Content-Type: application/x-tar' \
	--upload-file "$AIRFLOW_PROJECT_PATH/dags.tar" | grep x-ms-version-id | awk -F': ' '{print $2}')
	
	VERSION_ID=$(echo $VERSION_ID | sed 's/\r//g') # Remove unexpected carriage return characters
	echo -e "\nTar file uploaded with version: $VERSION_ID\n"
	
	# Finalizing Deploy
	FINALIZE_DEPLOY=$(curl --location --request POST "https://api.astronomer.io/platform/v1beta1/organizations/$ORGANIZATION_ID/deployments/$DEPLOYMENT_ID/deploys/$DEPLOY_ID/finalize" \
	--header "X-Astro-Client-Identifier: script" \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $ASTRO_API_TOKEN" \
	--data '{"dagTarballVersion": "'$VERSION_ID'"}')
	
	ID=$(echo $FINALIZE_DEPLOY | jq -r '.id')
	if [[ "$ID" != null ]]; then
	        echo -e "\nDeploy is Finalized. Image and DAG changes for deployment $DEPLOYMENT_ID should be live in a few minutes"
	        echo "Deployed Image tag: $TAG"
	        echo "Deployed DAG Tarball Version: $VERSION_ID"
	else
	        MESSAGE=$(echo $FINALIZE_DEPLOY | jq -r '.message')
	        if  [[ "$MESSAGE" != null ]]; then
	                echo $MESSAGE
	        else
	                echo "Something went wrong. Reach out to astronomer support for assistance"
	        fi
	fi
	
	# Cleanup
	echo -e "\nCleaning up the created tar file from $AIRFLOW_PROJECT_PATH/dags.tar"
	rm -rf "$AIRFLOW_PROJECT_PATH/dags.tar" 
fi
