
# NIDM-Results for SPM

Export mass-univariate neuroimaging results computed in SPM as NIDM-Results packs.

A *NIDM-Results pack* is a compressed file containing a NIDM-Results serialization and some or all of the referenced image data files in compliance with [NIDM-Results specification](http://nidm.nidash.org/specs/nidm-results.html).

## Usage
1. In Matlab, open `SPM`

   ```
   spm fmri
   ```
1. Open the `Batch Editor` by clicking on the `Batch` button in the SPM12 `Menu` window
1. Open the menu `SPM` > `Stats` > `Results Report` (Fig. 1.)
3. In the batch window  (Fig. 2.)
  - Fill in information about the results you are interested in (in particular `SPM.mat` file, contrast number, threshold, etc.)
  - In `Export results`, selected `New: NIDM (Neuroimaging Data Model)`
  - Fill in information about your analysis (`Modality`, `Reference space`, `Groups`etc.``) 

<img src="doc/batch_results_report.png" width="500">            |  <img src="doc/batch_export_NIDM.png" width="500">
:-------------------------:|:-------------------------:
 **Fig. 1.** Results report  |  **Fig. 2.** NIDM export
 
  
## Requirements
  - [SPM12](http://www.fil.ion.ucl.ac.uk/spm/software/spm12/)

## Install
  - The latest version of the NIDM exporter in available in the last SPM release (v. xx)

## How to run the tests?

### Copy test data
Test data is available at https://github.com/incf-nidash/nidmresults-examples/, you will need a local copy of this repository stored with [git lfs](https://git-lfs.github.com/):
```
cd test/data
git clone https://github.com/incf-nidash/nidmresults-examples.git
git lfs install
```

### Run the tests

To run the tests, you will need to install [docker](https://docs.docker.com/install/).

Then from the top folder of this repository, run:
```
did=$(docker run -it -d --rm -v `pwd`/test:/test -v `pwd`/exporter:/exporter cmaumet/octave-spm)
docker exec -it $did octave --no-window-system --eval "addpath('/exporter'); addpath('/test'); nidm_export_all('/test/data/nidmresults-examples', '/test/spmexport')"
python test/TestSPMResultDataModel.py
```
