# Custom Container to closely mimic an sklearn pre-built container
ARG FOUNDRY_ARTIFACTS_CLIENT_ID
ARG FOUNDRY_ARTIFACTS_CLIENT_SECRET

# Use the basic python 3.10 base image
FROM python:3.10-slim-bookworm as build-base

ARG OSDK_ENV
ARG FOUNDRY_ARTIFACTS_CLIENT_ID
ARG FOUNDRY_ARTIFACTS_CLIENT_SECRET

RUN apt-get update && apt-get upgrade -y libexpat1 
RUN apt-get install -y curl 

# Copy the python dependencies and code to be executed
COPY requirements.txt requirements.txt

RUN FOUNDRY_TOKEN=$(curl -X POST -d "grant_type=client_credentials&client_id=${FOUNDRY_ARTIFACTS_CLIENT_ID}&client_secret=${FOUNDRY_ARTIFACTS_CLIENT_SECRET}" https://domain.palantirfoundry.com/multipass/api/oauth2/token | grep -oP '"access_token"\s*:\s*"\K[^"]*') && \
    if [ "${OSDK_ENV}" = "prod" ]; then \
        pip install --upgrade pip && \
        pip install soevertexprd_sdk --upgrade --extra-index-url "https://:${FOUNDRY_TOKEN}@domain.palantirfoundry.com/artifacts/api/repositories/ri.artifacts.main.repository.7c3d8279-19b2-4165-aac1-8bc865cbbbbb/contents/release/pypi/simple" --extra-index-url "https://:${FOUNDRY_TOKEN}@domain.palantirfoundry.com/artifacts/api/repositories/ri.foundry-sdk-asset-bundle.main.artifacts.repository/contents/release/pypi/simple" --no-cache-dir && \
        pip install -r requirements.txt --no-cache-dir; \
    else \
        pip install --upgrade pip && \
        pip install soevertexdev_sdk --upgrade --extra-index-url "https://:${FOUNDRY_TOKEN}@domain.palantirfoundry.com/artifacts/api/repositories/ri.artifacts.main.repository.b49cdc75-419d-4b03-a9ce-b41d57bbe6d8/contents/release/pypi/simple" --extra-index-url "https://:${FOUNDRY_TOKEN}@domain.palantirfoundry.com/artifacts/api/repositories/ri.foundry-sdk-asset-bundle.main.artifacts.repository/contents/release/pypi/simple" --no-cache-dir && \
        pip install -r requirements.txt --no-cache-dir; \
    fi

###### build-test
FROM build-base as build-test

COPY /models/lrsp_snoe/requirements_tests.txt requirements_tests.txt
# put the test depdencies in their own folder for copying to test layer
RUN mkdir -p /home/gmi/project/test_deps && \
    pip install -r requirements_tests.txt --target /home/gmi/project/test_deps --no-cache-dir

###### local-base
FROM python:3.10-slim-bookworm as local-base

RUN apt-get update && apt-get upgrade -y libexpat1
COPY --from=build-base /usr/local/lib/python3.10/site-packages/ /usr/local/lib/python3.10/site-packages/.
COPY /models/lrsp_snoe/SoeLrsp/* SoeLrsp/

#copy ml pipeline utilities into image
COPY ../shared_libs/ml_pipeline_util/* SoeLrsp/

WORKDIR /SoeLrsp
    
# Run the python training script
ENTRYPOINT ["python", "model.py"]

###### local-base-test
FROM local-base as local-base-test
COPY --from=build-test /home/gmi/project/test_deps /home/gmi/project/test_deps
COPY /models/lrsp_snoe/SoeLrspTests/* /SoeLrspTests/
ENV PYTHONPATH=${PYTHONPATH}:/home/gmi/project/test_deps
#RUN python -m pylint -E -d E0401 .  #currently not passable, philip todo
#RUN python -m black --check .  #currently not passable, philip todo
RUN python -m pytest -s /SoeLrspTests
RUN echo done > /var/tmp/tests-done.txt

###### final
FROM local-base as final
#this COPY lets us make sure tests run when switching to docker buildx
#and allows final image to not have to have test tools installed
#https://github.com/docker/build-push-action/issues/377
COPY --from=local-base-test /var/tmp/tests-done.txt /var/tmp/tests-done.txt
