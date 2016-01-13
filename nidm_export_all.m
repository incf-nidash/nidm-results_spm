function nidm_export_all(path_to, out_path)
    if ~isvarname('out_path')
        out_path = '';
    end

    spm('defaults','fmri');
    spm_jobman('initcfg');
    spm_get_defaults('cmdline',true);

    files = dir(path_to);
    subdirs = files([files.isdir]);
    for i = 1:numel(subdirs)
        dname = subdirs(i).name;
        if ~strcmp(dname, 'spm_explicit_mask')
            % TODO: read config.json instead to check for software used
            if strncmpi(dname,'spm_',4)
                if ~strcmp(dname, 'ground_truth')
                    disp(dname)
                    nidm_export(fullfile(path_to, dname), out_path)
                end
            end
        end
    end
end