function priors = loadpriors(options, priorspec)

% phi
% -----
priors.phi_a = f_vec(zeros(options.Ns,options.Ns*options.Np)); % mean
pi1_phi_f = 0.2; % hyperparameter governing overall shrinkage
pi2_phi_f = 0.1; % hyperparameter governing shrinkage of lags belonging to other variables
pi3_phi_f = 2; % hyperparameter governing the degree of decay

temp = NaN(options.Ns,options.Ns,options.Np);
for p=1:options.Np
    % shrink coefficient on other lags by pi2!
    temp(1:options.Ns,1:options.Ns,p) = (pi2_phi_f/(p^pi3_phi_f))^(-1); % -> precision, not variance!
    for s=1:options.Ns
        % shrink coefficient on own lags by pi1!
        temp(s,s,p) = (pi1_phi_f/(p^pi3_phi_f))^(-1); % -> precision, not variance!           
    end
end

priors.phi_A = f_vec(reshape(temp,options.Ns,options.Ns*options.Np)'); % convert temp to RxR*P matrix, then take transpose and vectorize to make conformable with f_samplephi_f!!!         

% rho
% ------
priors.rho_a = zeros(options.Nj,1);
pi1_phi_eM = 0.2;
jj = 1:options.Nj;
priors.rho_A =  (pi1_phi_eM./(jj.^2)).^(-1); % -> precision, not variance!  


% Omega
% ------
priors.Omega_v = 3;
priors.Omega_delta = 1;
% priors.Omega_v = 0.1;
% priors.Omega_delta = 0.1;
% priors.Omega_v = 1001;
% priors.Omega_delta = 500;

% Sigma
% ------
priors.Sigma_v = options.Ns;
priors.Sigma_delta = eye(options.Ns);

% Normal-Gamma prior
% --------------------

if priorspec == 1
    priors.tau_v = 2;
    priors.tau_delta = 1;
end

% MG prior
% --------
if priorspec == 2
    priors.delta_b1 = 1;
    priors.delta_b2 = 1;
    priors.psi_upsilon = 3;
    priors.delta_a1 = 5;
    priors.delta_a2 = 2;
end

% PMNM prior
% -----------
if priorspec == 3
    priors.r0 = 5;
    priors.s0 = 0.5;
    priors.tau_v = 2;
    priors.tau_delta = 1;
end

% horseshoe prior
% -----------
if priorspec == 4
    priors.flagHSplus = 1 ; 
end

% diffuse Normal prior
% -----------
if priorspec == 5
    priors.lambdaP = 1/10 * ones(options.Nr,1) ; 
end

function x = f_vec(X)

%
%
[m , n] = size(X);
x = reshape(X,m*n,1);
