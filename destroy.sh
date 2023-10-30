#!/bin/bash

# main 폴더가 존재하는지 확인
if [ -d "main" ]; then
  # main 폴더가 존재하는 경우
  echo "main 폴더가 존재"
  cd main
  # 이제 main 폴더 내에서 원하는 작업을 수행합니다.
  terraform destroy -auto-approve
else
  # 현재 디렉토리에서 terraform destroy를 실행
  terraform destroy -auto-approve
fi
