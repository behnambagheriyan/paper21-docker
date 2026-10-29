# =============================================================================
# Paper 21 — Hosseini et al., Nature 642, 421–430 (2025)
# "Metformin reduces the competitive advantage of Dnmt3a R878H HSPCs"
# CITE-seq reproduction (GEO GSE254822)
#
# Built on the lab JupyterHub template (hedgelab/catcher). Adds two isolated
# R environments, each registered as a Jupyter kernel:
#
#   1. "R 4.1 · Paper21 (Seurat 4)"   -> /opt/micromamba/envs/p21_main
#        main analysis: Seurat 4, AUCell, scuttle, edgeR, clusterProfiler
#   2. "R 4.3 · Paper21 scDblFinder"  -> /opt/micromamba/envs/p21_dbl
#        doublet detection only (scDblFinder 1.16.0 requires R 4.3)
#
# Versions stated in the paper's Methods vs. versions installed here:
#   Seurat           v4        -> 4.3.0  (last v4 release built for R 4.1)
#   edgeR            3.36.0    -> 3.36.0 (exact)
#   clusterProfiler  4.2.2     -> 4.2.2  (conda 4.2.0 + 4.2.2 patch from Bioconductor 3.14)
#   scDblFinder      1.16.0    -> 1.16.0 (exact, separate R 4.3 env)
#   scuttle          1.0.4     -> 1.4.0  (1.0.4 requires R 4.0; aggregateAcrossCells
#                                         sum is deterministic, so the result is unaffected)
#   Cell Ranger      6.1.2     -> not needed (GEO provides the filtered matrices)
# The paper's versions come from 3 different Bioconductor releases
# (3.12, 3.14, 3.18) and cannot coexist in a single R installation.
# =============================================================================

FROM hedgelab/catcher:latestMaria

USER root

ARG PYVER=3.11.11

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    wget \
    curl \
    bzip2 \
    ca-certificates \
    zlib1g-dev \
    libncurses5-dev \
    libgdbm-dev \
    libnss3-dev \
    libssl-dev \
    libreadline-dev \
    libffi-dev \
    libsqlite3-dev \
    libbz2-dev \
    liblzma-dev \
    tk-dev \
    uuid-dev

# ---- Python + JupyterHub single-user server (unchanged from lab template) ----
RUN mkdir -p /tmp/python-src /home/python4Jup \
    && wget -O /tmp/python-src/Python.tgz https://www.python.org/ftp/python/${PYVER}/Python-${PYVER}.tgz \
    && cd /tmp/python-src \
    && tar -xzf Python.tgz \
    && cd Python-${PYVER} \
    && ./configure --prefix=/home/python4Jup --with-ensurepip=install \
    && make -j"$(nproc)" \
    && make install

RUN /home/python4Jup/bin/python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

RUN /home/python4Jup/bin/python3 -m pip install --no-cache-dir \
        jupyterhub==5.3.0 \
        jupyterlab \
        notebook \
        ipykernel \
    && useradd -m jovyan || true \
    && mkdir -p /home/python4Jup/share/jupyter/kernels

RUN /home/python4Jup/bin/python3 -m ipykernel install \
        --prefix=/home/python4Jup \
        --name py-homepython4jup \
        --display-name "Python (/home/python4Jup)" \
    && if [ -x /usr/local/anaconda/bin/python3 ]; then \
         /usr/local/anaconda/bin/python3 -m pip install --no-cache-dir ipykernel && \
         /usr/local/anaconda/bin/python3 -m ipykernel install \
           --prefix=/home/python4Jup \
           --name py-anaconda-base \
           --display-name "Python (anaconda base)"; \
       fi \
    && if [ -d /usr/local/anaconda/envs ]; then \
         for py in /usr/local/anaconda/envs/*/bin/python3; do \
           if [ -x "$py" ]; then \
             envname="$(basename "$(dirname "$(dirname "$py")")")"; \
             "$py" -m pip install --no-cache-dir ipykernel && \
             "$py" -m ipykernel install \
               --prefix=/home/python4Jup \
               --name "py-${envname}" \
               --display-name "Python (${envname})" || true; \
           fi; \
         done; \
       fi

RUN if command -v R >/dev/null 2>&1; then \
         R -e "if (!requireNamespace('IRkernel', quietly=TRUE)) install.packages('IRkernel', repos='https://cloud.r-project.org')" && \
         PATH="/home/python4Jup/bin:$PATH" R -e "IRkernel::installspec(user = FALSE, name = 'ir', displayname = 'R', prefix='/home/python4Jup')"; \
       fi \
    && chown -R jovyan:jovyan /home/jovyan /home/python4Jup \
    && rm -rf /var/lib/apt/lists/* /tmp/python-src

# =============================================================================
# Paper 21 environments
# =============================================================================

# ---- micromamba (pinned) ----
ENV MAMBA_ROOT_PREFIX=/opt/micromamba
RUN mkdir -p /tmp/mm /opt/micromamba /opt/p21 \
    && wget -q -O /tmp/mm/mm.tar.bz2 https://conda.anaconda.org/conda-forge/linux-64/micromamba-1.5.8-0.tar.bz2 \
    && tar -xjf /tmp/mm/mm.tar.bz2 -C /tmp/mm bin/micromamba \
    && mv /tmp/mm/bin/micromamba /usr/local/bin/micromamba \
    && rm -rf /tmp/mm

# Each env gets `.libPaths(.Library)` in its Rprofile.site right after creation, so R uses
# ONLY the env's own library (ignores R_LIBS / R_LIBS_USER set by the base image or the hub)
# and every later install lands inside the env.

# ---- Env 1: main analysis (R 4.1.3, Bioconductor 3.14) ----
RUN micromamba create -y -n p21_main --override-channels -c conda-forge -c bioconda \
        r-base=4.1.3 \
        r-seurat=4.3.0 \
        r-seuratobject=4.1.3 \
        bioconductor-edger=3.36.0 \
        bioconductor-clusterprofiler=4.2.0 \
        bioconductor-aucell=1.16.0 \
        bioconductor-scuttle=1.4.0 \
        bioconductor-singlecellexperiment \
        bioconductor-summarizedexperiment \
        bioconductor-affy \
        bioconductor-fgsea \
        bioconductor-org.mm.eg.db \
        r-dplyr \
        r-tidyr \
        r-patchwork \
        r-ggplot2 \
        r-rcolorbrewer \
        r-viridis \
        r-ggalluvial \
        r-irkernel \
        r-remotes \
        r-biocmanager \
    && micromamba clean -a -y \
    && echo '.libPaths(.Library)' >> /opt/micromamba/envs/p21_main/lib/R/etc/Rprofile.site

# Bioconductor data packages download their payload in a conda post-link script,
# which can fail silently. Re-install any that are missing from Bioconductor 3.14.
RUN /opt/micromamba/envs/p21_main/bin/Rscript -e ' \
      cat("libPaths:", .libPaths(), "\n"); \
      need <- c("GenomeInfoDbData","GO.db","DO.db","org.Mm.eg.db"); \
      have <- function(p) suppressPackageStartupMessages(requireNamespace(p, quietly = TRUE)); \
      miss <- need[!sapply(need, have)]; \
      cat("Missing data packages:", if (length(miss)) miss else "none", "\n"); \
      if (length(miss)) BiocManager::install(miss, version = "3.14", lib = .Library, update = FALSE, ask = FALSE, force = TRUE); \
      still <- need[!sapply(need, have)]; \
      if (length(still)) stop("Still missing after BiocManager: ", paste(still, collapse = ", "))'

# clusterProfiler 4.2.0 -> 4.2.2 (patch release used in the paper; pure R, same dependencies)
RUN cd /tmp \
    && ( wget -q https://bioconductor.org/packages/3.14/bioc/src/contrib/clusterProfiler_4.2.2.tar.gz \
         || wget -q https://bioconductor.org/packages/3.14/bioc/src/contrib/Archive/clusterProfiler/clusterProfiler_4.2.2.tar.gz ) \
    && /opt/micromamba/envs/p21_main/bin/R CMD INSTALL -l /opt/micromamba/envs/p21_main/lib/R/library clusterProfiler_4.2.2.tar.gz \
    && rm -f clusterProfiler_4.2.2.tar.gz \
    || echo "WARNING: clusterProfiler 4.2.2 could not be installed - keeping 4.2.0 (record this in the report)"

# ---- Env 2: doublet detection (R 4.3, Bioconductor 3.18) ----
# xgboost pinned to 1.7: the 3.x R API is not compatible with scDblFinder 1.16
RUN micromamba create -y -n p21_dbl --override-channels -c conda-forge -c bioconda \
        r-base=4.3 \
        bioconductor-scdblfinder=1.16.0 \
        r-xgboost=1.7 \
        bioconductor-singlecellexperiment \
        r-matrix \
        r-irkernel \
    && micromamba clean -a -y \
    && echo '.libPaths(.Library)' >> /opt/micromamba/envs/p21_dbl/lib/R/etc/Rprofile.site

RUN /opt/micromamba/envs/p21_dbl/bin/Rscript -e ' \
      if (!requireNamespace("GenomeInfoDbData", quietly = TRUE)) { \
        if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager", lib = .Library, repos = "https://cloud.r-project.org"); \
        BiocManager::install("GenomeInfoDbData", version = "3.18", lib = .Library, update = FALSE, ask = FALSE, force = TRUE) }; \
      stopifnot(requireNamespace("GenomeInfoDbData", quietly = TRUE))'


# ---- Build-time check: fail the build if any package does not load ----
RUN /opt/micromamba/envs/p21_main/bin/Rscript -e ' \
      pk <- c("Seurat","SeuratObject","sctransform","edgeR","limma","clusterProfiler","fgsea", \
              "AUCell","scuttle","SingleCellExperiment","SummarizedExperiment","org.Mm.eg.db", \
              "affy","dplyr","tidyr","patchwork","ggplot2","RColorBrewer","viridis","ggalluvial","Matrix"); \
      ok <- sapply(pk, function(p) tryCatch({ suppressPackageStartupMessages(loadNamespace(p)); TRUE }, \
              error = function(e) { message("LOAD ERROR ", p, ": ", conditionMessage(e)); FALSE })); \
      if (!all(ok)) stop("Failed to load: ", paste(pk[!ok], collapse = ", ")); \
      v <- sapply(pk, function(p) as.character(packageVersion(p))); \
      writeLines(c(R.version.string, paste(pk, v, sep = "\t")), "/opt/p21/versions_p21_main.txt")' \
    && /opt/micromamba/envs/p21_dbl/bin/Rscript -e ' \
      pk <- c("scDblFinder","SingleCellExperiment","xgboost","Matrix"); \
      ok <- sapply(pk, function(p) tryCatch({ suppressPackageStartupMessages(loadNamespace(p)); TRUE }, \
              error = function(e) { message("LOAD ERROR ", p, ": ", conditionMessage(e)); FALSE })); \
      if (!all(ok)) stop("Failed to load: ", paste(pk[!ok], collapse = ", ")); \
      v <- sapply(pk, function(p) as.character(packageVersion(p))); \
      writeLines(c(R.version.string, paste(pk, v, sep = "\t")), "/opt/p21/versions_p21_dbl.txt")' \
    && cat /opt/p21/versions_*.txt

# ---- Exact lock files (record of every installed package, for the report) ----
RUN micromamba env export -n p21_main --explicit > /opt/p21/p21_main.lock.txt \
    && micromamba env export -n p21_dbl  --explicit > /opt/p21/p21_dbl.lock.txt

# ---- Register both envs as Jupyter kernels ----
RUN PATH="/home/python4Jup/bin:$PATH" /opt/micromamba/envs/p21_main/bin/R -e \
      "IRkernel::installspec(user = FALSE, name = 'r-p21-main', displayname = 'R 4.1 · Paper21 (Seurat 4)', prefix = '/home/python4Jup')" \
    && PATH="/home/python4Jup/bin:$PATH" /opt/micromamba/envs/p21_dbl/bin/R -e \
      "IRkernel::installspec(user = FALSE, name = 'r-p21-dbl', displayname = 'R 4.3 · Paper21 scDblFinder', prefix = '/home/python4Jup')" \
    && chown -R jovyan:jovyan /home/jovyan /home/python4Jup /opt/micromamba /opt/p21

ENV HOME=/home/jovyan
WORKDIR /home/jovyan
USER jovyan

ENTRYPOINT []
CMD ["/home/python4Jup/bin/jupyterhub-singleuser", "--allow-root"]
