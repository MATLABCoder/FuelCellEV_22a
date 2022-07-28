function varargout = GenerateMappedFuelCellCalibrations(varargin)
% Copyright 2021 The MathWorks, Inc.
%% Setup
Block = varargin{1};
isMBCInstalled = CheckMBCLicense(Block);
varargout{1} = [];
if isMBCInstalled || strcmp('SpreadsheetFileNameSelect', varargin{2})
    switch varargin{2}
        case 'SpreadsheetFileNameSelect'
            SpreadsheetFileNameSelect(Block);
        case 'GenMappedFCellCalButton'
            GenMappedFCellCalButton(Block);
        case 'ApplyCalMappedFCellButton'
            ApplyCalMappedFCellButton(Block);
        case 'CheckMBCLicense'
            CheckMBCLicense(Block);
        case 'OpenMBCFile'
            OpenMBCFile(Block);
        case 'OpenCageFile'
            OpenCageFile(Block);
        case 'Init'
            CheckMBCLicense(Block);
        case 'UpdateParentIcon'
            UpdateParentIcon(Block)
    end
end


end

%% ExcelFileNameSelect
function SpreadsheetFileNameSelect(Block)
[FileName, PathName] = uigetfile('*.xlsx');
if ~ischar(FileName)
    return;
end
FilesFound = which(FileName, '-ALL');
if length(FilesFound) ~= 1
    FileName = [PathName, FileName];
else
    if ~strcmp([PathName, FileName], FilesFound{1})
        FileName = [PathName, FileName];
    end
end
set_param(Block,'SpreadsheetFileName', FileName);

end

%% CreateResSurfMdlButton
function GenMappedFCellCalButton(Block)
%% Open MBC if user info requested
P = mbcprefs('mbc');
if ~getpref(P, 'UserInfoRequested')
    mbcmodel;
end

%% Get File names
% Spreadsheet file name
[PathName, FileName, Ext] = fileparts(get_param(Block,'SpreadsheetFileName'));
if isempty(PathName)
    SelectedFile = which([FileName, Ext]);
    PathName = fileparts(SelectedFile);
end
XlsFileName = [PathName, '\', FileName, Ext];

% MBC project name
MBCFileName = GetMBCPrjName(Block);

% Cage file name
CageFileName = GetCageFileName(Block);

% Model reference name
MappedFCellMdlRefName = get_param(Block, 'MappedFCellMdlRefName');

%% Determine breakpoint type and template file names
if bdIsLoaded(MappedFCellMdlRefName)
    isSysLoaded = true;
else
    load_system(MappedFCellMdlRefName)
    isSysLoaded = false;
end

if ~isSysLoaded
    load_system(MappedFCellMdlRefName)
end

CageTemplate=autoblkssharedFullMbcTemplateName('MappedFuelCellTemplate.cag');

TestPlanName = autoblkssharedFullMbcTemplateName('MappedFuelCell.mbt');

%% Waitbar setup
wh = waitbar(0, 'Generating mapped fuel cell calibration');

%% Fit models in MBC
MBCProject = mbcmodel.CreateProject(MBCFileName);
WaitbarFrac(wh, 0.1);

% Define column names
SignalNames = {'CurrentCmd', 'TempCmd', 'AuxPower', 'HeatFlow','Voltage', 'H2Flow'}; ...
SignalUnits = {'A','degC','W','W','V','kg/s'};

% Dataset
Data = CreateData(MBCProject,XlsFileName,'auto');
Data = SetupMBCData(Data, SignalNames, SignalUnits, SignalNames, wh);
Testplan = CreateTestplan(MBCProject, TestPlanName);
WaitbarFrac(wh, 0.2);
AttachData(Testplan,Data,'UseDataRange',true,'Boundary',true);
WaitbarFrac(wh, 0.6);


%% Fill tables using Cage

% Get all models
mdls = children(MBCProject.Object,@getBestExportModel);
mdls = [mdls{:}];

% filter warning message as in g2577130
ws=warning('OFF','mbc:xregpointer:PointerMatch');
restoreWarning = onCleanup(@() warning(ws));

% Load templates and import model
cgp=load(CageTemplate,'-mat');
cgp = cgp.PROJ;

Bpt1Name = 'f_fc_tmpcmd_bpt';
Bpt2Name = 'f_fc_currcmd_bpt';

% Update breakpoints
Bpt1 = findItem(cgp,'Name', Bpt1Name);
dataRanges = getranges(mdls{1});
BptVals1 = get(info(Bpt1),'breakpoints');
BptVals1(:) = linspace(dataRanges(1,2), dataRanges(2,2), numel(BptVals1))';

Bpt2 = findItem(cgp,'Name', Bpt2Name);
dataRanges = getranges(mdls{1});
BptVals2 = get(info(Bpt2),'breakpoints');
BptVals2(:) = linspace(dataRanges(1,1), dataRanges(2,1), numel(BptVals2))';

% Update breakpoint values
updateBptVals(cgp, Bpt1Name, BptVals1);
updateBptVals(cgp, Bpt2Name, BptVals2);
updateOptimVals(cgp)
updateFeatureBpts(cgp)

WaitbarFrac(wh, 0.9);

% Refill tables
importModels(cgp,mdls,[],[],true);
WaitbarFrac(wh, 1);

%% Save and open files
% MBC
SaveAs(MBCProject, MBCFileName);
mbcmodel(MBCFileName)
rMBCMODEL = get(MBrowser,'RootNode');
if ~isempty(rMBCMODEL)
    file = rMBCMODEL.projectfile;
    
    % select Power model
    tp = rMBCMODEL.children(1);
    power = tp.children(1);
    SelectNode(MBrowser, power);
end


% Cage
projectfile(info(cgp), CageFileName);
save(info(cgp));
cage(CageFileName);
pCAGE = get(cgbrowser,'RootNode');
if ~isempty(pCAGE) 
    file = pCAGE.projectfile;
    
    % select 
    pTable = pCAGE.findItem('Name','f_fc_auxpower','node');
    gotonode(cgbrowser,pTable,xregpointer);
end

%% Close waitbar
if ishandle(wh)
    close(wh)
end

end

%% GenMappedFCellButton
function ApplyCalMappedFCellButton(Block)

% filter warning message as in g2577130
ws=warning('OFF','mbc:xregpointer:PointerMatch');
restoreWarning = onCleanup(@() warning(ws));

%% Load cage file
CageFileName = GetCageFileName(Block);
try
    cgp = info(get(cgbrowser,'RootNode'));
catch
   cgp = []; 
end
if isempty(cgp) || ~strcmp(CageFileName,projectfile(cgp))
    % get 
    CageFileName = GetCageFileName(Block);
    cgp = load(CageFileName,'-mat');
    cgp = cgp.PROJ;
    isCageLoaded = true;
else
    isCageLoaded = false;
end

%% Add tables to model workspace
% Get file name
MappedFCellMdlRefName = get_param(Block, 'MappedFCellMdlRefName');
MappedFCellMdlRefFullName = which(MappedFCellMdlRefName);

% Export tables to Simulink Model Workspace
% cal=calibrationdata.matvariableinterface('filename',MappedFCellMdlRefFullName);
% calout = cgcaloutput(address(cgp),cal);
% SL_WKSP_file(calout);

calibrationdata.internal.export('MATVariableInterface',MappedFCellMdlRefFullName,getCalibrationItems(cgp))
if isCageLoaded
    % close temporary CAGE project
    delete(info(cgp));
end

% Close model
pause(1)
clear cal calout

close_system(MappedFCellMdlRefName, 1);

end

%% OpenMBCFile
function OpenMBCFile(Block)
MBCFileName = GetMBCPrjName(Block);
mbcmodel(MBCFileName)
end

%% OpenCageFile
function OpenCageFile(Block)
CageFileName = GetCageFileName(Block);
cage(CageFileName);
end

%% WaitbarFrac
function WaitbarFrac(wh, Frac)
    if ishandle(wh)
       waitbar(Frac, wh); 
    end
end

%% CheckMBCLicense
function isMBCInstalled = CheckMBCLicense(Block)
MaskObj = Simulink.Mask.get(Block);  
GenMappedFCellCalButton = MaskObj.getDialogControl('GenMappedFCellCalButton');
ApplyCalMappedFCellButton = MaskObj.getDialogControl('ApplyCalMappedFCellButton');
MBCIconImg = MaskObj.getDialogControl('MBCIconImg');

if license('test', 'MBC_Toolbox')
    GenMappedFCellCalButton.Enabled = 'on';
    ApplyCalMappedFCellButton.Enabled = 'on';
    MBCIconImg.Enabled = 'on';
    MBCIconImg.Visible = 'on';
    isMBCInstalled = true;   
else
    GenMappedFCellCalButton.Enabled = 'off';
    ApplyCalMappedFCellButton.Enabled = 'off';
    MBCIconImg.Enabled = 'off';
    MBCIconImg.Visible = 'off';
    isMBCInstalled = false;
end

end

%% UpdateParentIcon
function UpdateParentIcon(Block)
while ~isempty(get_param(Block,'Parent'))
    set_param(Block, 'Position', get_param(Block,'Position'))
    Block = get_param(Block,'Parent');
end
end

%% GetMBCPrjName
function MBCFileName = GetMBCPrjName(Block)
[~, FileName] = fileparts(get_param(Block,'MBCProjectName'));
FullMfileName = mfilename('fullpath');
PathName = fileparts(FullMfileName);
Ext = '.mat';
if ~isempty(PathName)
    PathName = [PathName, '\'];
end
MBCFileName = [PathName, FileName, Ext];
end

%% GetCageFileName
function CageFileName = GetCageFileName(Block)
[~, FileName] = fileparts(get_param(Block,'CageFileName'));
FullMfileName = mfilename('fullpath');
PathName = fileparts(FullMfileName);
Ext = '.cag';
if ~isempty(PathName)
    PathName = [PathName, '\'];
end
CageFileName = [PathName, FileName, Ext];
end

%% SetupMBCData
function Data = SetupMBCData(Data, AllNames, AllUnits, RequiredNames, wh)

% Check required data
for i = 1:length(RequiredNames)
    if ~any(strcmp(RequiredNames{i}, Data.SignalNames))
        if ishandle(wh)
            close(wh)
        end
        WorksheetName = 'Fuel Cell Performance Data';
        error(getString(message('autoblks:autoblkErrorMsg:errSheetCol', WorksheetName, RequiredNames{i})))  
    end
end

% Add variables for missing columns
Data.BeginEdit;
for i = 1:length(AllNames)
    if ~any(strcmp(AllNames{i}, Data.SignalNames))
        Data.AddVariable([AllNames{i}, ' = 0'], AllUnits{i});
    end
end
Data.CommitEdit;
end



%% updateBptVals
function updateBptVals(cgp, BptName, BptVals)
    BptPtr = findItem(cgp,'Name', BptName);
    BptPtr.info = set(info(BptPtr),'breakpoints',BptVals);
end

%% updateOptimVals
function updateOptimVals(cgp)
pTables = findItem(cgp,'type','Table','data');
pOptim = findItem(cgp,'type','Optimization','data');
pInps = cell(size(pTables));

for j = 1:length(pTables)
    pInps{j} = getinports(pTables(j).info);
end
for i=1:length(pOptim)
    optim = pOptim(i).info;
    [pVal, ~] = getfixedvaluedata(optim);
    for j = 1:length(pTables) 
        [OK,~]=ismember(pInps{j},pVal);
        if all(OK)
            pOptim(i).info = setinitialvaluedatafromtablegrid(optim,pTables(j));
            break;
        end
    end
end
    
end

%% updateFeatureBpts
function updateFeatureBpts(cgp)
    pFeature = findItem(cgp,'type','Feature','data');
    for i = 1:length(pFeature)
        FeatureFill = get(info(pFeature(i)),'cgsimfill');
        for j = 1:length(FeatureFill)
            ValCell = FeatureFill(j).Values;
            ValNames = ValCell(1:round(length(ValCell)/2));
            FillVals = ValCell((round(length(ValCell)/2)+1):end);
            
            Normalizers = info(get(FeatureFill(j).Tables.Object, 'normalizers'));
            NumNorm = length(Normalizers);
            
            
            for k = 1:NumNorm
                NormName = get(Normalizers{k},'xname');
                NormSelect = strcmp(NormName, ValNames);
                if any(NormSelect)
                    if length(FillVals{NormSelect}) > 1
                        FillVals{NormSelect} = get(Normalizers{k},'allbreakpoints');
                    end
                end
            end
            NewValCell = cell(size(ValCell));
            for k = 1:length(ValNames)
                NewValCell{2*(k-1)+1} = ValNames{k};
                NewValCell{2*(k-1)+2} = FillVals{k};
            end
            FeatureFill(j).Values = NewValCell;
        end
    end
end
