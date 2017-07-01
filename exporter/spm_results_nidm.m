function [nidmfile, prov] = spm_results_nidm(SPM,xSPM,TabDat,opts)
% Export SPM stats results using the Neuroimaging Data Model (NIDM)
% FORMAT [nidmfile, prov] = spm_results_nidm(SPM,xSPM,TabDat,opts)
% SPM      - structure containing analysis details (see spm_spm.m)
% xSPM     - structure containing inference details (see spm_getSPM.m)
% TabDat   - structure containing results details (see spm_list.m)
% opts     - structure containing extra information about:
%   .group - subject/group(s) under study
%   .mod   - data modality
%   .space - reference space
%
% nidmfile - output NIDM zip archive filename
% prov     - provenance object (see spm_provenance.m)
%__________________________________________________________________________
% References:
% 
% Neuroimaging Data Model (NIDM):
%   http://nidm.nidash.org/
%
% PROV-DM: The PROV Data Model:
%   http://www.w3.org/TR/prov-dm/
%__________________________________________________________________________
% Copyright (C) 2013-2017 Wellcome Trust Centre for Neuroimaging

% Guillaume Flandin
% $Id: spm_results_nidm.m 6903 2016-10-12 11:36:41Z guillaume $


%-Get input parameters, interactively if needed
%==========================================================================
if nargin && ischar(SPM) && strcmpi(SPM,'upload')
    if nargin > 2
        upload_to_neurovault(xSPM,TabDat); % token
    else
        upload_to_neurovault(xSPM);
    end
    return;
end

if nargin < 1
    [SPM,xSPM] = spm_getSPM;
elseif nargin < 2
    if isstruct(SPM)
        xSPM = struct('swd',SPM.swd);
    else
        xSPM = struct('swd',spm_file('cpath',SPM));
    end
    [SPM,xSPM] = spm_getSPM(xSPM);
end
if nargin < 3
    % Consider Inf local maxima more than 0mm apart (i.e. all)
    TabDat = spm_list('Table',xSPM,Inf,0);
end
if nargin < 4
    opts = struct;
end

nidm_json = struct();

%-Options
%==========================================================================

%-General options
%--------------------------------------------------------------------------
gz          = '.gz';                         %-Compressed NIfTI {'.gz', ''}
NIDMversion = '1.3.0';
SVNrev      = '$Rev: 6903 $';

%-Reference space
%--------------------------------------------------------------------------
if ~isfield(opts,'space')
    s1 = {'Subject space','Normalised space (using Segment)',...
        'Normalised space (using Old Segment)','Custom space',...
        'Other normalised MNI space','Other normalised Talairach space'};
    s2 = {'subject','ixi','icbm','custom','mni','talairach'};
    opts.space = spm_input('Reference space :',1,'m',s1);
    opts.space = s2{opts.space};
end
switch opts.space
    case 'subject'
        coordsys = 'nidm_SubjectCoordinateSystem';
    case 'ixi'
        coordsys = 'nidm_Ixi549CoordinateSystem';
    case 'icbm'
        coordsys = 'nidm_IcbmMni152LinearCoordinateSystem';
    case 'custom'
        coordsys = 'nidm_CustomCoordinateSystem';        
    case 'mni'
        coordsys = 'nidm_MNICoordinateSystem';        
    case 'talairach'
        coordsys = 'nidm_TalairachCoordinateSystem';  
    otherwise
        error('Unknown reference space.');
end
nidm_json.CoordinateSpace_inWorldCoordinateSystem = coordsys;

%-Data modality
%--------------------------------------------------------------------------
MRIProtocol  = '';
if ~isfield(opts,'mod')
    m1 = {'Anatomical MRI','functional MRI','Diffusion MRI','PET','SPECT','EEG','MEG'};
    m2 = {'AMRI','FMRI','DMRI','PET','SPECT','EEG','MEG'};
    opts.mod = spm_input('Data modality :','+1','m',m1);
    opts.mod = m2{opts.mod};
end
switch opts.mod
    case 'AMRI'
        ImagingInstrument = 'nlx_Magneticresonanceimagingscanner';
        MRIProtocol       = 'nlx_AnatomicalMRIprotocol';    
    case 'FMRI'
        ImagingInstrument = 'nlx_Magneticresonanceimagingscanner';
        MRIProtocol       = 'nlx_FunctionalMRIprotocol';
    case 'DMRI'
        ImagingInstrument = 'nlx_Magneticresonanceimagingscanner';
        MRIProtocol       = 'nlx_DiffusionMRIprotocol';
    case 'PET'
        ImagingInstrument = 'nlx_Positronemissiontomographyscanner';
    case 'SPECT'
        ImagingInstrument = 'nlx_Singlephotonemissioncomputedtomographyscanner';
    case 'EEG'
        ImagingInstrument = 'nlx_Electroencephalographymachine';
    case 'MEG'
        ImagingInstrument = 'nlx_Magnetoencephalographymachine';
    otherwise
        error('Unknown modality.');
end

%-Subject/Group(s)
%--------------------------------------------------------------------------
if ~isfield(opts,'group')
    opts.group.N = spm_input('Number of subjects per group :','+1','e');
    if isequal(opts.group.N,1)
        opts.group.name = {'single subject'};
    else
        for i=1:numel(opts.group.N)
            opts.group.name{i} = spm_input(...
                sprintf('Name of group %d :',i),'+1','s');
        end
    end
end
groups = opts.group;

%-Units
%--------------------------------------------------------------------------
try
    units = xSPM.units;
catch
    try
        units = SPM.xVol.units;
    catch
        units = {'mm' 'mm' 'mm'};
    end
end

%==========================================================================
%-Populate output directory
%==========================================================================
if ~exist(SPM.swd,'dir'), SPM.swd = pwd; end

temp_img = {}; % TODO % create a temp directory to store intermediate files

%-Design Matrix values
%--------------------------------------------------------------------------
nidm_json.DesignMatrix_value = SPM.xX.xKXs.X;
nidm_json.DesignMatrix_regressorNames = SPM.xX.name;

%-Maximum Intensity Projection image (as png)
%--------------------------------------------------------------------------
nidm_json.CoordinateSpace_voxelUnits = units;

files.mip = fullfile(SPM.swd,'MaximumIntensityProjection.png');
MIP       = spm_mip(xSPM.Z,xSPM.XYZmm,xSPM.M,units);
imwrite(MIP,gray(64),files.mip,'png');

temp_img{end+1} = files.mip;

%-Beta images (as NIfTI)
%--------------------------------------------------------------------------
for i=1:numel(SPM.Vbeta)
    files.beta{i} = fullfile(xSPM.swd,SPM.Vbeta(i).fname);
end

%-SPM{.}, contrast, contrast standard error, and contrast explained mean square images (as NIfTI)
%--------------------------------------------------------------------------
for i=1:numel(xSPM.Ic)
    if numel(xSPM.Ic) == 1, postfix = '';
    else                    postfix = sprintf('_%04d',i); end
    files.spm{i} = fullfile(xSPM.swd,SPM.xCon(xSPM.Ic(i)).Vspm.fname);
    if xSPM.STAT == 'T'
        files.con{i} = fullfile(xSPM.swd,SPM.xCon(xSPM.Ic(i)).Vcon.fname);
        
        files.conse{i} = fullfile(xSPM.swd,['ContrastStandardError' postfix '.nii' gz]);
        Vc = SPM.xCon(xSPM.Ic(i)).c' * SPM.xX.Bcov * SPM.xCon(xSPM.Ic(i)).c;
        img2nii(fullfile(xSPM.swd,SPM.VResMS.fname), files.conse{i}, struct('fcn',@(x) sqrt(x*Vc)));
        temp_img{end+1} = files.conse{i};
    elseif xSPM.STAT == 'F'
        files.effms{i} = fullfile(xSPM.swd,['ContrastExplainedMeanSquare' postfix '.nii' gz]);
        eidf = SPM.xCon(xSPM.Ic(i)).eidf;
        img2nii(fullfile(xSPM.swd,SPM.xCon(xSPM.Ic(i)).Vcon.fname), files.effms{i}, struct('fcn',@(x) x/eidf));
        temp_img{end+1} = files.effms{i};
    end
end

%-Thresholded SPM{.} image (as NIfTI)
%--------------------------------------------------------------------------
files.tspm = fullfile(xSPM.swd,['ExcursionSet.nii' gz]);
if ~isempty(gz), files.tspm = spm_file(files.tspm,'ext',''); end
spm_write_filtered(xSPM.Z,xSPM.XYZ,xSPM.DIM,xSPM.M,'',files.tspm);
if ~isempty(gz), gzip(files.tspm); spm_unlink(files.tspm); files.tspm = [files.tspm gz]; end
temp_img{end+1} = files.tspm;

%-Residual Mean Squares image (as NIfTI)
%--------------------------------------------------------------------------
files.resms = fullfile(xSPM.swd,SPM.VResMS.fname);

%-Resels per Voxel image (as NIfTI)
%--------------------------------------------------------------------------
files.rpv = fullfile(xSPM.swd,SPM.xVol.VRpv.fname);

%-Analysis mask image (as NIfTI)
%--------------------------------------------------------------------------
files.mask = fullfile(xSPM.swd,SPM.VM.fname);

%-Grand mean image (as NIfTI)
%--------------------------------------------------------------------------
files.grandmean = fullfile(xSPM.swd,'GrandMean.nii');

sf  = mean(SPM.xX.xKXs.X,1);
Vb  = SPM.Vbeta;
for i=1:numel(Vb), Vb(i).pinfo(1:2,:) = Vb(i).pinfo(1:2,:) * sf(i); end
Vgm = struct(...
    'fname',   files.grandmean,...
    'dim',     Vb(1).dim,...
    'dt',      [spm_type('float32') spm_platform('bigend')],...
    'mat',     Vb(1).mat,...
    'pinfo',   [1 0 0]',...
    'descrip', 'Grand Mean');
Vgm = spm_create_vol(Vgm);
Vgm.pinfo(1,1) = spm_add(Vb,Vgm);
Vgm = spm_create_vol(Vgm);
if ~isempty(gz), gzip(files.grandmean); spm_unlink(files.grandmean); files.grandmean = [files.grandmean gz]; end
temp_img{end+1} = files.grandmean;

%-Explicit mask image (as NIfTI)
%--------------------------------------------------------------------------
if ~isempty(SPM.xM.VM)
    files.emask = fullfile(xSPM.swd,['CustomMask.nii' gz]);
    temp_img{end+1} = files.emask;
    
    if isempty(spm_file(SPM.xM.VM.fname,'path'))
        Vem = fullfile(xSPM.swd,SPM.xM.VM.fname);
    else
        Vem = SPM.xM.VM.fname;
    end
    img2nii(Vem, files.emask);
else
    files.emask = '';
end

%-Clusters n-ary image (as NIfTI)
%--------------------------------------------------------------------------
files.clust = fullfile(xSPM.swd,['ClusterLabels.nii' gz]);
temp_img{end+1} = files.clust;
if ~isempty(gz), files.clust = spm_file(files.clust,'ext',''); end
Z   = spm_clusters(xSPM.XYZ);
idx = find(~cellfun(@isempty,{TabDat.dat{:,5}}));
n   = zeros(1,numel(idx));
for i=1:numel(idx)
    [unused,j] = spm_XYZreg('NearestXYZ',TabDat.dat{idx(i),12}',xSPM.XYZmm);
    n(i) = Z(j);
end
n(n) = 1:numel(n);
if max(Z) ~= numel(idx)
    warning('Small Volume Correction not handled yet.');
    n(numel(idx)+1:max(Z)) = 0;
end
Z    = n(Z);
spm_write_filtered(Z,xSPM.XYZ,xSPM.DIM,xSPM.M,'',files.clust);
if ~isempty(gz), gzip(files.clust); spm_unlink(files.clust); files.clust = [files.clust gz]; end

%-Display mask images (as NIfTI)
%--------------------------------------------------------------------------
for i=1:numel(xSPM.Im)
    files.dmask{i} = fullfile(xSPM.swd,[sprintf('DisplayMask_%04d.nii',i) gz]);
    temp_img{end+1} = files.dmask{i};
    if isnumeric(xSPM.Im)
        um = spm_u(xSPM.pm,[SPM.xCon(xSPM.Im(i)).eidf,SPM.xX.erdf],...
            SPM.xCon(xSPM.Im(i)).STAT);
        if ~xSPM.Ex, fcn = @(x) x > um;
        else         fcn = @(x) x <= um; end
        img2nii(SPM.xCon(xSPM.Im(i)).Vspm.fname, files.dmask{i}, struct('fcn',fcn));
    else
        if ~xSPM.Ex, fcn = @(x) x~=0 & ~isnan(x);
        else         fcn = @(x) ~(x~=0 & ~isnan(x)); end
        img2nii(xSPM.Im{i}, files.dmask{i}, struct('fcn',fcn));
    end
end
if numel(xSPM.Im) == 0, files.dmask = {}; end

%-SVC Mask (as NIfTI)
%--------------------------------------------------------------------------
if strcmp(TabDat.tit,'p-values adjusted for search volume')
    files.svcmask = '';
elseif strncmp(TabDat.tit,'search volume: ',15)
    warning('Small Volume Correction not handled yet.'); % see spm_VOI.m
    % '%0.1fmm sphere at [%.0f,%.0f,%.0f]'
    % '%0.1f x %0.1f x %0.1f mm box at [%.0f,%.0f,%.0f]'
    % 'image mask: %s'
    files.svcmask = '';
else
    warning('Unable to retrieve search volume details: assuming whole brain search.');
    files.svcmask = '';
end

%-Search Space mask image (as NIfTI)
%--------------------------------------------------------------------------
files.searchspace = fullfile(xSPM.swd,SPM.VM.fname);


%==========================================================================
%-                          D A T A   M O D E L
%==========================================================================

%-Provenance
%--------------------------------------------------------------------------
[V,R] = spm('Ver');

nidm_json.NIDMResultsExporter_type = 'spm_results_nidm';
nidm_json.NIDMResultsExporter_softwareVersion = [V(4:end) '.' char(regexp(SVNrev,'\$Rev: (\w.*?) \$','tokens','once'))];
nidm_json.NIDMResults_version = NIDMversion;

%-Agent: SPM
%--------------------------------------------------------------------------
nidm_json.NeuroimagingAnalysisSoftware_type = 'src_SPM';
nidm_json.NeuroimagingAnalysisSoftware_label = 'SPM';
nidm_json.NeuroimagingAnalysisSoftware_softwareVersion = [V(4:end) '.' R];

%-Agent: Scanner
%--------------------------------------------------------------------------
nidm_json.Imaginginstrument_type = ImagingInstrument;

%-Agent: Person
%--------------------------------------------------------------------------
if ~isequal(groups.N,1)
    %-Agent: Group
    %----------------------------------------------------------------------
    for i=1:numel(groups.N)
        nidm_json.Groups(i).studygrouppopulation_groupName = groups.name{i};
        nidm_json.Groups(i).studygrouppopulation_numberOfSubjects = groups.N(i);
    end
end

%-Entity: Image Data
%--------------------------------------------------------------------------
if isfield(SPM,'Sess')
    nidm_json.Data_grandMeanScaling = true;
    nidm_json.Data_targetIntensity = SPM.xGX.GM;
else
    nidm_json.Data_grandMeanScaling = false;
end
if ~isempty(MRIProtocol)
    nidm_json.Data_hasMRIProtocol = MRIProtocol;
end

%-Entity: Drift Model
%--------------------------------------------------------------------------
if isfield(SPM,'Sess') && isfield(SPM.xX,'K')
    nidm_json.DesignMatrix_hasDriftModel = 'spm_DiscreteCosineTransformbasisDriftModel';
    nidm_json.DesignMatrix_SPMsDriftCutoffPeriod = SPM.xX.K(1).HParam;
end

%-Entity: Design Matrix
%--------------------------------------------------------------------------
if isfield(SPM,'xBF')
    switch SPM.xBF.name
        case 'hrf'
            nidm_json.DesignMatrix_hasHRFBasis = {'spm_SPMsCanonicalHRF'};
        case 'hrf (with time derivative)'
            nidm_json.DesignMatrix_hasHRFBasis = {'spm_SPMsCanonicalHRF', 'spm_SPMsTemporalDerivative'};
        case 'hrf (with time and dispersion derivatives)'
            nidm_json.DesignMatrix_hasHRFBasis = {'spm_SPMsCanonicalHRF', 'spm_SPMsTemporalDerivative', 'spm_SPMsDispersionDerivative'};
        case 'Finite Impulse Response'
            nidm_json.DesignMatrix_hasHRFBasis = {'nidm_FiniteImpulseResponseBasisSet'};
        case 'Fourier set'
            nidm_json.DesignMatrix_hasHRFBasis = {'nidm_FourierBasisSet'};
        case 'Gamma functions'
            nidm_json.DesignMatrix_hasHRFBasis = {'nidm_GammaBasisSet'};
        case {'Fourier set (Hanning)'}
            warning('Not implemented "%s".',SPM.xBF.name);
        otherwise
            warning('Unknown basis set.');
    end
end

%-Entity: Explicit Mask
%--------------------------------------------------------------------------
if ~isempty(SPM.xM.VM)
    nidm_json.CustomMap_atLocation = files.emask;
end

%-Entity: Error Model
%--------------------------------------------------------------------------
if isfield(SPM.xVi,'form')
    if strcmp(SPM.xVi.form,'i.i.d')
        nidm_json.ErrorModel_errorVarianceHomogeneous = true;
        nidm_json.ErrorModel_hasErrorDependence = 'nidm_IndependentError';
        nidm_json.ModelParameterEstimation_withEstimationMethod = 'obo_ordinaryleastsquaresestimation';
    else
        nidm_json.ErrorModel_errorVarianceHomogeneous = true;
        nidm_json.ErrorModel_hasErrorDependence = 'obo_Toeplitzcovariancestructure';
        nidm_json.ErrorModel_dependenceMapWiseDependence = 'nidm_ConstantParameter';
        nidm_json.ErrorModel_varianceMapWiseDependence = 'nidm_IndependentParameter';
        nidm_json.ModelParameterEstimation_withEstimationMethod = 'obo_generalizedleastsquaresestimation';
    end
else
    if ~isfield(SPM.xVi,'Vi') || numel(SPM.xVi.Vi) == 1 % assume it's identity
        nidm_json.ErrorModel_errorVarianceHomogeneous = true;
        nidm_json.ErrorModel_hasErrorDependence = 'nidm_IndependentError';
        nidm_json.ErrorModel_varianceMapWiseDependence = 'nidm_IndependentParameter';
        nidm_json.ModelParameterEstimation_withEstimationMethod = 'obo_ordinaryleastsquaresestimation';
    else
        nidm_json.ErrorModel_errorVarianceHomogeneous = false;
        nidm_json.ErrorModel_hasErrorDependence = 'obo_unstructuredcovariancestructure';
        nidm_json.ErrorModel_dependenceMapWiseDependence = 'nidm_ConstantParameter';
        nidm_json.ErrorModel_varianceMapWiseDependence = 'nidm_IndependentParameter';
        nidm_json.ModelParameterEstimation_withEstimationMethod = 'obo_generalizedleastsquaresestimation';
    end
end

nidm_json.ErrorModel_hasErrorDistribution = 'obo_normaldistribution';

%-Activity: Model Parameters Estimation
%==========================================================================

%-Entity: Mask Map
%--------------------------------------------------------------------------
nidm_json.MaskMap_atLocation = uri(spm_file(files.mask,'cpath'));

%-Entity: Grand Mean Map
%--------------------------------------------------------------------------
nidm_json.GrandMeanMap_atLocation = uri(spm_file(files.grandmean,'cpath'));

%-Entity: Parameter Estimate (Beta) Maps
%--------------------------------------------------------------------------
for i=1:numel(SPM.Vbeta)
    nidm_json.ParameterEstimateMaps{i} = uri(files.beta{i});
end

%-Entity: ResMS Map
%--------------------------------------------------------------------------
nidm_json.ResidualMeanSquaresMap_atLocation = uri(spm_file(files.resms,'cpath'));

%-Entity: RPV Map
%--------------------------------------------------------------------------
nidm_json.ReselsPerVoxelMap_atLocation = uri(spm_file(files.rpv,'cpath'));

%-Activity: Contrast Estimation
%==========================================================================
STAT = xSPM.STAT;
if STAT == 'T', STAT = lower(STAT); end

contrast_names = cell(1,numel(xSPM.Ic));

for c=1:numel(xSPM.Ic)
    con_name = nidm_esc(SPM.xCon(xSPM.Ic(c)).name);
    contrast_names{c} = con_name;
    if xSPM.STAT == 'T'
        nidm_json.Contrasts(c) = struct(...
            'StatisticMap_contrastName', con_name, ...
            'contrastweightmatrix_value', SPM.xCon(xSPM.Ic(c)).c', ...
            'StatisticMap_statisticType', ['obo_' STAT 'statistic'], ...
            'StatisticMap_errorDegreesOfFreedom', xSPM.df(2), ...
            'StatisticMap_atLocation', uri(spm_file(files.spm{c},'cpath')), ...
            'ContrastMap_atLocation', uri(spm_file(files.con{c},'cpath')), ...
            'ContrastStandardErrorMap_atLocation', uri(spm_file(files.conse{c},'cpath')));
    end
    if xSPM.STAT == 'F'
        nidm_json.Contrasts(c) = struct(...
            'StatisticMap_contrastName', con_name, ...
            'obo_contrastweightmatrix/prov:value', SPM.xCon(xSPM.Ic(c)).c', ...
            'StatisticMap_statisticType', ['obo_' STAT 'statistic'], ...
            'StatisticMap_errorDegreesOfFreedom', xSPM.df(2), ...
            'StatisticMap_effectDegreesOfFreedom', xSPM.df(1), ...
            'StatisticMap_atLocation', uri(spm_file(files.spm{c},'cpath')), ...
            'ContrastExplainedMeanSquareMap_atLocation', uri(uri(spm_file(files.effms{c},'cpath'))));
    end
end

%-Entity: Height Threshold
%--------------------------------------------------------------------------
thresh(1).type  = 'obo_statistic';
thresh(1).label = 'Height Threshold';
thresh(1).value = xSPM.u; % TabDat.ftr{1,2}(1)
thresh(2).type  = 'nidm_PValueUncorrected';
thresh(2).label = 'Height Threshold';
thresh(2).value = TabDat.ftr{1,2}(2);
thresh(3).type  = 'obo_FWERadjustedpvalue';
thresh(3).label = 'Height Threshold';
thresh(3).value = TabDat.ftr{1,2}(3);
td = regexp(xSPM.thresDesc,'p\D?(?<u>[\.\d]+) \((?<thresDesc>\S+)\)','names');
if isempty(td)
    td = regexp(xSPM.thresDesc,'\w=(?<u>[\.\d]+)','names');
    if ~isempty(td)
        thresh_order = 1:3; % Statistic
        thresh_desc  = sprintf(': %s=%f)',xSPM.STAT,xSPM.u);
    else
        warning('Unkwnown threshold type.');
        thresh_order = 1:3; % unknown
        thresh_desc  = '';
    end
else
    switch td.thresDesc
        case 'FWE'
            thresh_order = [3 1 2]; % FWE
            thresh_desc  = sprintf(': p<%f (FWE)',TabDat.ftr{1,2}(3));
        case 'unc.'
            thresh_order = [2 1 3]; % uncorrected
            thresh_desc  = sprintf(': p<%f (unc.)',TabDat.ftr{1,2}(2));
            % Set uncorrected p-value threshold to the user-defined value
            % (to avoid possible floating point approximations)            
            %thresh(2).value = str2double(td.u);
        case 'FDR'
            thresh(3).type  = 'obo_qvalue';
            thresh(3).label = 'Height Threshold';
            thresh(3).value = str2double(td.u);
            thresh_order = [3 1 2]; % FDR
            thresh_desc  = sprintf(': p<%s (FDR)',td.u);
        otherwise
            warning('Unkwnown threshold type.');
            thresh_order = 1:3; % unknown
            thresh_desc  = '';
    end
end
thresh = thresh(thresh_order);
thresh(1).label = [thresh(1).label thresh_desc];

%-Entity: Extent Threshold
%--------------------------------------------------------------------------
if spm_get_defaults('stats.rft.nonstat')
    warning('Non-stationary RFT results not handled yet.');
end
V2R = 1 / prod(xSPM.FWHM);

if TabDat.ftr{2,2}(1) > 0
    kk = [TabDat.ftr{2,2}(2) TabDat.ftr{2,2}(3)];
else
    kk = [1 1];
end

nidm_inference = struct();
nidm_inference.HeightThreshold_type = thresh(1).type;
nidm_inference.HeightThreshold_value = thresh(1).value;
nidm_inference.ExtentThreshold_type = 'obo_statistic';
nidm_inference.ExtentThreshold_clusterSizeInVoxels = TabDat.ftr{2,2}(1);
nidm_inference.ExtentThreshold_clusterSizeInResels = TabDat.ftr{2,2}(1)*V2R;

nidm_height_equivthresh = struct();
nidm_extent_equivthresh = struct();
ex_equiv_types = {'obo_FWERadjustedpvalue', 'nidm_PValueUncorrected'};
for i = 2:3
    nidm_height_equivthresh(i-1).HeightThreshold_type =  thresh(i).type;
    nidm_height_equivthresh(i-1).HeightThreshold_value = thresh(i).value;
    nidm_extent_equivthresh(i-1).ExtentThreshold_type = ex_equiv_types{i-1};
     % SPM equiv thresholds are always p-values (i.e. not cluster sizes)
    nidm_extent_equivthresh(i-1).ExtentThreshold_value = kk(i-1);
end
nidm_inference.HeightThreshold_equivalentThreshold = nidm_height_equivthresh;
nidm_inference.ExtentThreshold_equivalentThreshold = nidm_extent_equivthresh;

%-Entity: Peak & Cluster Definition Criteria
%--------------------------------------------------------------------------
% TabDat.str = 'table shows %d local maxima more than %.1fmm apart'
maxNumberOfPeaksPerCluster = spm_get_defaults('stats.results.volume.nbmax');
minDistanceBetweenPeaks = spm_get_defaults('stats.results.volume.distmin');
clusterConnectivityCriterion = 18; % see spm_max.m

nidm_json.ClusterDefinitionCriteria_hasConnectivityCriterion = ...
    sprintf('nidm_voxel%dconnected',clusterConnectivityCriterion);
nidm_json.PeakDefinitionCriteria_minDistanceBetweenPeaks = ...
    minDistanceBetweenPeaks;
nidm_json.PeakDefinitionCriteria_maxNumberOfPeaksPerCluster = ...
    maxNumberOfPeaksPerCluster;
    
%-Activity: Inference
%==========================================================================
nidm_inference.Inference_hasAlternativeHypothesis = 'nidm_OneTailedTest';
if numel(xSPM.Ic) == 1
    conj = false;
else
    conj = true;
    nidm_inference.nidm_contrastName = contrast_names;
    if xSPM.n == 1
        nidm_inference.Inference_type = 'nidm_ConjunctionInference';
    else
        nidm_inference.Inference_type = 'spm_PartialConjunctionInference';
        nidm_inference.PartialConjunctionInference_partialConjunctionDegree = xSPM.n;
    end
end

%-Entity: Display Mask Maps
%--------------------------------------------------------------------------
for i=1:numel(files.dmask)
    nidm_inference.DisplayMaskMap_atLocation = uri(spm_file(files.dmask{i},'cpath'));
end

%-Entity: SVC Mask Map
%--------------------------------------------------------------------------
if ~isempty(files.svcmask)
    nidm_inference.SubVolumeMap_atLocation = uri(spm_file(files.svcmask,'cpath'));    
end

%-Entity: Search Space
%--------------------------------------------------------------------------
nidm_inference.SearchSpaceMaskMap_atLocation = uri(spm_file(files.searchspace,'cpath'));
nidm_inference.SearchSpaceMaskMap_searchVolumeInVoxels = xSPM.S;    
nidm_inference.SearchSpaceMaskMap_searchVolumeInUnits = TabDat.ftr{8,2}(1);    
nidm_inference.SearchSpaceMaskMap_reselSizeInVoxels = TabDat.ftr{9,2}(end);
nidm_inference.SearchSpaceMaskMap_searchVolumeInResels = TabDat.ftr{8,2}(3);
nidm_inference.SearchSpaceMaskMap_searchVolumeReselsGeometry = xSPM.R;
nidm_inference.SearchSpaceMaskMap_noiseFWHMInVoxels = xSPM.FWHM;
nidm_inference.SearchSpaceMaskMap_noiseFWHMInUnits = TabDat.ftr{7,2}(1:3);
nidm_inference.SearchSpaceMaskMap_randomFieldStationarity = ...
    ~spm_get_defaults('stats.rft.nonstat');
nidm_inference.SearchSpaceMaskMap_expectedNumberOfVoxelsPerCluster = TabDat.ftr{3,2};
nidm_inference.SearchSpaceMaskMap_expectedNumberOfClusters = TabDat.ftr{4,2};
nidm_inference.SearchSpaceMaskMap_heightCriticalThresholdFWE05 = xSPM.uc(1);
nidm_inference.SearchSpaceMaskMap_heightCriticalThresholdFDR05 = xSPM.uc(2);

if isfinite(xSPM.uc(3))
    nidm_inference.SearchSpaceMaskMap_smallestSignificantClusterSizeInVoxelsFWE05 = xSPM.uc(3);
end
if isfinite(xSPM.uc(4))
    nidm_inference.SearchSpaceMaskMap_smallestSignificantClusterSizeInVoxelsFDR05 = xSPM.uc(4);
end

%-Entity: Excursion Set
%--------------------------------------------------------------------------
if size(TabDat.dat,1) > 0
    c  = TabDat.dat{1,2};
    pc = TabDat.dat{1,1};
else
    c  = 0;
    pc = NaN;
end

nidm_inference.ExcursionSetMap_atLocation = uri(spm_file(files.tspm,'cpath'));
nidm_inference.ExcursionSetMap_numberOfSupraThresholdClusters = c;
nidm_inference.ExcursionSetMap_pValue = pc;

nidm_inference.ClusterLabelsMap_atLocation = uri(spm_file(files.clust,'cpath'));
nidm_inference.ExcursionSetMap_hasMaximumIntensityProjection = uri(spm_file(files.mip,'cpath'));


%-Entity: Peaks & Clusters
%--------------------------------------------------------------------------
nidm_clusters = struct();

idx = find(~cellfun(@isempty,{TabDat.dat{:,5}}));

clustidx = cumsum(~cellfun(@isempty,{TabDat.dat{:,5}}));

for i=1:numel(idx)    
    nidm_clusters(i).SupraThresholdCluster_clusterSizeInVoxels = TabDat.dat{idx(i),5};
    nidm_clusters(i).SupraThresholdCluster_clusterSizeInResels = TabDat.dat{idx(i),5}*V2R;
    nidm_clusters(i).SupraThresholdCluster_pValueUncorrected = TabDat.dat{idx(i),6};
    nidm_clusters(i).SupraThresholdCluster_pValueFWER = TabDat.dat{idx(i),3};
    nidm_clusters(i).SupraThresholdCluster_qValueFDR = TabDat.dat{idx(i),4};
    
    %-Entity: Peaks
    %----------------------------------------------------------------------
    nidm_peaks = struct();
    k = 1;
    for j=1:size(TabDat.dat,1)
        if clustidx(j) == i
            nidm_peaks(k).Peak_value = TabDat.dat{j,9};
            nidm_peaks(k).Coordinate_coordinateVector = TabDat.dat{j,12}(1:3);
            nidm_peaks(k).Peak_pValueUncorrected = TabDat.dat{j,11};
            nidm_peaks(k).Peak_equivalentZStatistic = xsdfloat(TabDat.dat{j,10});
            nidm_peaks(k).Peak_pValueFWER = TabDat.dat{j,7};
            nidm_peaks(k).Peak_qValueFDR = TabDat.dat{j,8};
            k = k + 1;
        end
    end
    nidm_clusters(i).Peaks = nidm_peaks;
end

nidm_inference.Clusters = nidm_clusters;

if ~conj
    nidm_json.Inferences = nidm_inference;
else
    nidm_json.ConjunctionInferences = nidm_inference;    
end

[nidmfile, prov] = spm_nidmresults(nidm_json, SPM.swd);

for i = 1:numel(temp_img)
    spm_unlink(temp_img{i});
end

% % pp.bundle(idResults,p);
% 
% %==========================================================================
% %-                  P R O V   S E R I A L I Z A T I O N
% %==========================================================================
% %serialize(pp,fullfile(outdir,'nidm.provn'));
% serialize(pp,fullfile(outdir,'nidm.ttl'));
% try, serialize(pp,fullfile(outdir,'nidm.jsonld')); end
% %serialize(pp,fullfile(outdir,'nidm.json'));
% %serialize(pp,fullfile(outdir,'nidm.pdf'));
% 
% i = 1;
% while true
%     nidmfile = fullfile(SPM.swd,sprintf('spm_%04d.nidm.zip',i));
%     if spm_existfile(nidmfile), i = i + 1; else break; end
% end
% f = zip(nidmfile,'*',outdir);
% for i=1:numel(f)
%     spm_unlink(fullfile(outdir,f{i}));
% end
% rmdir(outdir);
% 
% prov = pp;


%==========================================================================
% function v = xsdfloat(v)
%==========================================================================
function v = xsdfloat(v)
% See http://books.xmlschemata.org/relaxng/ch19-77095.html
if numel(v) == 1 && isinf(v) && v > 0, v = 'INF';  end
if numel(v) == 1 && isinf(v) && v < 0, v = '-INF'; end
if numel(v) == 1 && isnan(v),          v = 'NaN';  end


%==========================================================================
% function u = uri(u)
%==========================================================================
function u = uri(u)
%-File URI scheme
%if ispc, s='/'; else s=''; end
%u = ['file://' s strrep(spm_file(u,'cpath'),'\','/')];
e = ' ';
for i=1:length(e)
    u = strrep(u,e(i),['%' dec2hex(e(i))]);
end
u = spm_file(u,'filename');


%==========================================================================
% function img2nii(img,nii,xSPM)
%==========================================================================
function img2nii(img,nii,xSPM)
if nargin == 2, xSPM = struct; end
if ~isfield(xSPM,'STAT'), xSPM.STAT = ''; end
if ~isfield(xSPM,'fcn'), xSPM.fcn = @(x) x; end
if nargin == 1, nii = spm_file(img,'ext','.nii'); end
gz = strcmp(spm_file(nii,'ext'),'gz');
if gz, nii = spm_file(nii,'ext',''); end
ni     = nifti(img);
no     = nifti;
no.dat = file_array(nii,...
                    ni.dat.dim,...
                    ni.dat.dtype,...
                    0,...
                    ni.dat.scl_slope,...
                    ni.dat.scl_inter);
no.mat  = ni.mat;
no.mat_intent = ni.mat_intent;
no.mat0 = ni.mat0;
no.mat0_intent = ni.mat0_intent;
no.descrip = ni.descrip;
switch xSPM.STAT
    case 'T'
        no.intent.name  = ['spm' xSPM.STATstr];
        no.intent.code  = 3;
        no.intent.param = xSPM.df(2);
    case 'F'
        no.intent.name  = ['spm' xSPM.STATstr];
        no.intent.code  = 4;
        no.intent.param = xSPM.df;
    case 'con'
        no.intent.name  = 'SPM contrast';
        no.intent.code  = 1001;
end

create(no);
no.dat(:,:,:) = xSPM.fcn(ni.dat(:,:,:));
if gz
    gzip(nii);
    spm_unlink(nii);
end


%==========================================================================
% function make_ROI(fname,DIM,M,xY)
%==========================================================================
function make_ROI(fname,DIM,M,xY)
gz = strcmp(spm_file(fname,'ext'),'gz');
if gz, fname = spm_file(fname,'ext',''); end
R = struct(...
    'fname',  fname,...
    'dim',    DIM,...
    'dt',     [spm_type('uint8'), spm_platform('bigend')],...
    'mat',    M,...
    'pinfo',  [1,0,0]',...
    'descrip','ROI');
Q    = zeros(DIM);
[xY, XYZmm, j] = spm_ROI(xY, struct('dim',DIM,'mat',M));
Q(j) = 1;
R    = spm_write_vol(R,Q);
if gz
    gzip(R.fname);
    spm_unlink(R.fname);
end


%==========================================================================
% function S = nidm_esc(S)
%==========================================================================
function S = nidm_esc(S)
S = strrep(S, sprintf('\n'), '\n');


%==========================================================================
% Upload to NeuroVault
%==========================================================================
function upload_to_neurovault(nidmfile,token)

neurovault = 'http://neurovault.org';

% Get token
if nargin > 1
    addpref('neurovault','token',token);
elseif ispref('neurovault','token')
    token = getpref('neurovault','token');
else
    if spm('CmdLine')
        error('Upload to NeuroVault requires a token-based authentication.');
    end
    fprintf([...
        'To set up integration with NeuroVault you need to obtain a\n',...
        'secret token first. Please go to http://neurovault.org/ and\n',...
        'generate a new token. To complete the procedure you will need\n',...
        'to log into NeuroVault. If you don''t have an account you can\n',...
        'create one or simply log in using Facebook or Google. When you\n',...
        'generated a token (a string of 40 random characters), copy it\n',...
        'into the dialog box. If you ever lose access to this machine\n',...
        'you can delete the token on NeuroVault.org thus preventing\n',...
        'unauthorized parties to access your NeuroVault data\n']);
    token = inputdlg('Token','Enter NeuroVault token',1,{''},'on');
    if isempty(token) || isempty(token{1}), return; else token = char(token); end
    addpref('neurovault','token',token);
end
auth = ['Bearer ' token];

% Check token
url = [neurovault '/api/my_collections/'];
statusCode = http_request('head', url, 'Authorization', auth);
if isnan(statusCode)
    error('Cannot connect to NeuroVault.');
elseif statusCode ~= 200
    warning('Failed authentication with NeuroVault: invalid token.');
    rmpref('neurovault','token');
    upload_to_neurovault(nidmfile);
    return;
end

% Get user name
url = [neurovault '/api/user/'];
[statusCode, responseBody] = http_request('jsonGet', url, 'Authorization', auth);
if statusCode == 200
    responseBody = spm_jsonread(responseBody);
    owner_name = responseBody.username;
else
    err = spm_jsonread(responseBody);
    error(char(err.detail));
end
my_collection = sprintf('%s''s %s Collection',owner_name,spm('Ver'));

% Get the list of collections
url   = [neurovault '/api/my_collections/'];
[statusCode, responseBody] = http_request('jsonGet', url, 'Authorization', auth);
if statusCode == 200
    collections = spm_jsonread(responseBody);
else
    err = spm_jsonread(responseBody);
    error(char(err.detail));
end

% Create a new collection if needed
id = NaN;
for i=1:numel(collections.results)
    if strcmp(collections.results(i).name,my_collection)
        id = collections.results(i).id;
        break;
    end
end
if isnan(id)
    url   = [neurovault '/api/collections/'];
    requestParts = [];
    requestParts.Type = 'string';
    requestParts.Name = 'name';
    requestParts.Body = my_collection;
    [statusCode, responseBody] = http_request('multipartPost', url, requestParts, 'Authorization', auth);
    if statusCode == 201
        collections = spm_jsonread(responseBody);
        id = collections.id;
    else
        err = spm_jsonread(responseBody);
        error(char(err.name));
    end
end

% Upload NIDM-Results in NeuroVault's collection
url = [neurovault sprintf('/api/collections/%d/nidm_results/',id)];
requestParts = [];
requestParts(1).Type = 'string';
requestParts(1).Name = 'name';
requestParts(1).Body = 'No name'; % NAME
requestParts(2).Type = 'string';
requestParts(2).Name = 'description';
requestParts(2).Body = 'No description'; % DESCRIPTION
requestParts(3).Type = 'file';
requestParts(3).Name = 'zip_file';
requestParts(3).Body = nidmfile;
[statusCode, responseBody] = http_request('multipartPost', url, requestParts, 'Authorization', auth);
if statusCode == 201
    responseBody = spm_jsonread(responseBody);
    cmd = 'web(''%s'',''-browser'')';
    fprintf('Uploaded to %s\n',spm_file(responseBody.url,'link',cmd));
else
    err = spm_jsonread(responseBody);
    error(char(err.name));
end

%==========================================================================
% HTTP requests with missing-http
%==========================================================================
function varargout = http_request(action, url, varargin)
% Use missing-http from Paul Sexton:
% https://github.com/psexton/missing-http/

persistent jar_added_to_path
if isempty(jar_added_to_path)
    try
        net.psexton.missinghttp.MatlabShim;
    catch
        err = lasterror;
        if strcmp(err.identifier, 'MATLAB:dispatcher:noMatchingConstructor')
            jar_added_to_path = true;
        else
            jarfile = fullfile(spm('Dir'),'external','missing-http','missing-http.jar');
            if spm_existfile(jarfile)
                javaaddpath(jarfile); % this clears global
                jar_added_to_path = true;
            else
                error('HTTP library missing.');
            end
        end
    end
end

switch lower(action)
    case 'head'
        try
            response = char(net.psexton.missinghttp.MatlabShim.head(url, varargin));
        catch
            response = 'NaN';
        end
        statusCode   = str2double(response);
        varargout    = { statusCode };
    case 'jsonget'
        try
            response = cell(net.psexton.missinghttp.MatlabShim.jsonGet(url, varargin));
        catch
            response = {'NaN',''};
        end
        statusCode   = str2double(response{1});
        responseBody = response{2};
        varargout    = { statusCode, responseBody };
    case 'multipartpost'
        requestParts = varargin{1};
        crp = cell(1, numel(requestParts));
        for k=1:numel(requestParts)
            crp{k}   = sprintf('%s\n%s\n%s', requestParts(k).Type, requestParts(k).Name, requestParts(k).Body);
        end
        try
            response = cell(net.psexton.missinghttp.MatlabShim.multipartPost(url, crp, varargin(2:end)));
        catch
            response = {'NaN',''};
        end
        statusCode   = str2double(response{1});
        responseBody = response{2};
        varargout    = { statusCode, responseBody };
    otherwise
        error('Unknown HTTP request.');
end

%==========================================================================
% HTTP requests with MATLAB R2016b
%==========================================================================
function varargout = http_request2(action, url, varargin)

switch lower(action)
    case 'head'
        opt = weboptions('HeaderFields',varargin,'ContentType','text');
        try
            webread(url,opt); % it's a GET, not a HEAD
            statusCode = 200;
        catch
            err = lasterror;
            s = regexp(err.identifier,'MATLAB:webservices:HTTP(\d+)','tokens');
            if isempty(s)
                statusCode = NaN;
            else
                statusCode = str2double(s{1}{1});
            end
        end
        varargout    = { statusCode };
    case 'jsonget'
        opt = weboptions('HeaderFields',varargin,'ContentType','text');
        try
            responseBody = webread(url,opt);
            statusCode = 200;
        catch
            err = lasterror;
            s = regexp(err.identifier,'MATLAB:webservices:HTTP(\d+)','tokens');
            if isempty(s)
                statusCode = NaN;
            else
                statusCode = str2double(s{1}{1});
            end
        end
        varargout    = { statusCode, responseBody };
    case 'multipartpost'
        requestParts = varargin{1};
        opt = weboptions('HeaderFields',varargin(2:end),'ContentType','text');
        try
            responseBody = webread(url,opt);
            statusCode = 200;
        catch
            err = lasterror;
            s = regexp(err.identifier,'MATLAB:webservices:HTTP(\d+)','tokens');
            if isempty(s)
                statusCode = NaN;
            else
                statusCode = str2double(s{1}{1});
            end
        end
        varargout    = { statusCode, responseBody };
    otherwise
        error('Unknown HTTP request.');
end
