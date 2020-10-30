#!/bin/bash

UID="gerald"

radosgw-admin user create --uid="$UID" --display-name="Gerald Yang"

AK=$(radosgw-admin user info --uid="$UID" | jq -r ".keys[0].access_key")
SK=$(radosgw-admin user info --uid="$UID" | jq -r ".keys[0].secret_key")

cp s3cfg.template .s3cfg
sed -i "s/MY_ACCESS_KEY/$AK/g" .s3cfg
sed -i "s/MY_SECRET_KEY/$SK/g" .s3cfg

mv -f .s3cfg /root/.s3cfg
