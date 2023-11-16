START_DATE=${START_DATE:="2023-01-01"}
END_DATE=${END_DATE:="2023-12-31"}
ROOT_DIR=${PWD}
DATA_DIR=${ROOT_DIR}/querido-diario
OUT_DIR=${DATA_DIR}/out
REPO_DIR=${DATA_DIR}/qd
DATA_COLLECTION_DIR=${REPO_DIR}/data_collection
QD_DOWNLOAD_DIR=${REPO_DIR}/data_collection/data/2700000
DOWNLOAD_DIR=${DATA_DIR}/diarios

mkdir -p ${DATA_DIR}
cd ${DATA_DIR}
mkdir -p ${DOWNLOAD_DIR}
mkdir -p ${OUT_DIR}

# Preparando ambiente para coleta.
cd ${REPO_DIR} || (git clone https://github.com/okfn-brasil/querido-diario qd && cd ${REPO_DIR})
python -m venv .venv
source .venv/Scripts/activate
python -m pip install -r ${DATA_COLLECTION_DIR}/requirements-dev.txt --no-deps