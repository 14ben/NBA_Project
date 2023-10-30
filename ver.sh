#!/bin/bash

# 사용자로부터 버전 번호를 입력 받음
read -p "Enter the new version for [Jenkins,Pod] (ex: 2.2): " NEW_VERSION
read -p "Enter the new version for [Dockerfile, Pod] (ex: 03): " FILE_PART

if [ -n "$FILE_PART" ]; then

# Dockerfile 업데이트
  sed -i 's#COPY rev.[0-9]*_full_pro.sh /provision/#COPY rev.'$FILE_PART'_full_pro.sh /provision/#' Dockerfile
  sed -i 's#RUN chmod +x /provision/rev.[0-9]*_full_pro.sh#RUN chmod +x /provision/rev.'$FILE_PART'_full_pro.sh#' Dockerfile

  # pod.yaml 업데이트 
  sed -i 's#args: ["/provision/rev.[0-9]*_full_pro.sh#args: ["/provision/rev.'$FILE_PART'_full_pro.sh#' pod_full_provision.yaml
fi

if [ -n "$NEW_VERSION" ]; then
  # Jenkinsfile 업데이트
  sed -i 's#IMAGE_VERSION = "[0-9.]*"#IMAGE_VERSION = "'$NEW_VERSION'"#' Jenkinsfile

  # pod.yaml 업데이트
  sed -i 's#image: .*:.*$#image: 622164100401.dkr.ecr.ap-northeast-1.amazonaws.com/nba_full_provision:'$NEW_VERSION'#' pod_full_provision.yaml
fi


echo "Version updated to $NEW_VERSION in Jenkinsfile and pod.yaml"
echo "main.sh Version update to $FILE_PART in Dockerfile and pod.yaml"

