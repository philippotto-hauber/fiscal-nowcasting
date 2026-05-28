function [phi, Sigma, lambda, omega, rho] = f_startingvalues(data_m, data_q, options)
% ----------------------------------------------------------------------- %
% ----------------------------------------------------------------------- %

% -----------------------------------------
% - initial estimate of eta => PCA
% -----------------------------------------

[data_bal, balstart, balend, etaPCA] = f_startvals_factors(data_m,options) ;

% -----------------------------------------
% - initial estimate of phi and Sigma
% -----------------------------------------

[phi, Sigma] = f_startvals_phi_sigma(etaPCA,options) ;

% --------------------------------------------
% - initial estimate of lambda, omega & rho
% --------------------------------------------

% monthly vars
[lambdaM, omegaM, rhoM] = f_startvals_monthlyvars(data_bal,etaPCA,options) ;

% quarterly vars
[lambdaQ, omegaQ, rhoQ] = f_startvals_quarterlyvars(data_q,balstart,balend,etaPCA,options) ;

lambda = [lambdaM; lambdaQ] ;
omega = [omegaM; omegaQ] ;
rho = [rhoM; rhoQ] ; 

% ---FUNCTIONS----------------------------------------------------------- %
% ----------------------------------------------------------------------- %

function [data_bal, balstart, balend, factors] = f_startvals_factors(data_m,options)

[data_bal, balstart, balend] = f_findbalancedsubsample(data_m);

data_bal(isnan(data_bal)) = 0; % overwrite missing obs in middle of sample with 0!

[factors, ~] = f_PCA(data_bal,options.Ns); % use balanced dataset to obtain PCA estimates of factors


function [Y_bal, index_balanced_start, index_balanced_end] = f_findbalancedsubsample(Y)
%UNTITLED5 Summary of this function goes here
%   Detailed explanation goes here
[~,T] = size(Y);

% start of balanced subsample
for t=1:T;
    if any(isnan(Y(:,t)));
        
    else
        break
    end
end
index_balanced_start=t;

% end of balanced subsample
for t=T:-1:1;
     if any(isnan(Y(:,t)));
       
    else
        break
    end
end
index_balanced_end=t;


Y_bal = Y(:,index_balanced_start:index_balanced_end);

function [F_hat, V] = f_PCA(Y,R)
% covariance matrix of observables
SIGMA = Y*Y'/size(Y,2);

% eigenvalue and -vector decomposition
[V,D] = eig(SIGMA);

% extract eigenvalues and change order
eigenvalues_D = diag(D);
eigenvalues_D = flipud(eigenvalues_D);
D = diag(eigenvalues_D);
% change order of eigenvectors
V = f_reversecolumns(V);
F_hat = V(:,1:R)'*Y ;
%F_hat = F_hat(1:R,:);
V = V';

function [ A_reverse ] = f_reversecolumns( A )
%Reverses the columns of a matrix. 
aux = zeros(size(A));
[R,C] = size(A);
for c=0:(C-1);
    aux(:,c+1) = A(:,C-c);
end
A_reverse = aux;

function [phi, Sigma] = f_startvals_phi_sigma(factors,options)

y = factors(:,options.Np+1:end)';
X = [];
for l=1:options.Np
    X = [X factors(:,options.Np+1-l:end-l)'];
end
phi = (inv(X'*X)*X'*y)';

% keep draw if it satisfies stationarity
phi_companion = [phi;eye((options.Np-1)*options.Ns) zeros((options.Np-1)*options.Ns,options.Ns)];
          
if max(abs(eig(phi_companion)))>=1
    phi = [];
    for p = 1 : options.Np
        phi = [phi 0.1 * eye(options.Ns)];
    end
end

Sigma = eye(options.Ns) ; 

function [lambdaM, omegaM, rhoM] = f_startvals_monthlyvars(data_bal, factors,options)

lambdaM = NaN(options.Nm,options.Nr);
omegaM = NaN(options.Nm,1);
if options.Nj > 0 
    rhoM = NaN(options.Nm,options.Nj) ; 
else
    rhoM = zeros(options.Nm,1) ;
end

% regressor
Xetas = factors( : , options.Nr/options.Ns  : end  )' ; 
for s = 1 : options.Nr/options.Ns - 1
    Xetas = [Xetas factors( : , options.Nr/options.Ns - s : end - s )']; %(:,balstart:balend)';
end

for i=1:options.Nm
    % lambda_m
    Y = data_bal(i,:)' ; 
    Y = Y( options.Nr/options.Ns : end , 1 ) ; 
    % make sure no missings left in Y
    Yestim = Y(~isnan(Y(:,1)),1) ; 
    Xestim = Xetas(~isnan(Y(:,1)),:);
    lambdaM(i,:) = ((Xestim'*Xestim)\Xestim'*Yestim)';
    idios = Yestim - Xestim*lambdaM(i,:)';
        if options.Nj > 0
        y = idios(options.Nj+1:end,:);
        X = [];
        for j = 1 : options.Nj
            X = [X idios(options.Nj+1-j:end-j,:)];
        end
        rhoM( i , : ) = inv(X'*X)*X'*y;
        resids = y - X * rhoM( i , :)';
        omegaM(i,1) = var(resids);
    else
        omegaM(i,1) = idios'*idios/length(idios);
    end
end

function [lambdaQ, omegaQ, rhoQ] = f_startvals_quarterlyvars(data_q,balstart,balend,factors,options)

lambdaQ = NaN(options.Nq,options.Nr);
omegaQ = NaN(options.Nq,1);
if options.Nj > 0 
    rhoQ = NaN(options.Nq,options.Nj) ; 
else
    rhoQ = zeros(options.Nq,1) ;
end

for i=1:options.Nq
    temp = [NaN(size(factors,1),2) (factors(:,1:end-2)+factors(:,2:end-1)+factors(:,3:end))/3]; % quarterly averages of monthly factors
    y_prelim = data_q(i,balstart:balend)';
    y = y_prelim(~isnan(y_prelim));
    x_prelim = temp(:,~isnan(y_prelim))';
    
    % get rid of NaNs
    x = x_prelim(~isnan(x_prelim(:,1)),:);
    y = y(~isnan(x_prelim(:,1)),:);    
    
    % 
    y_estim = y(options.Nr/options.Ns:end,:) ; 
    x_estim = x(options.Nr/options.Ns:end,:) ; 
    for s = 1 : options.Nr/options.Ns - 1
        x_estim = [x_estim x( options.Nr/options.Ns - s : end - s , : )]; %(:,balstart:balend)';
    end
    
    % simple OLS    
    lambdaQ(i,:) = (x_estim'*x_estim)\x_estim'*y_estim;
    idios = y_estim-x_estim*lambdaQ(i,:)';
    if options.Nj > 0
        y = idios(options.Nj+1:end,:);
        X = [];
        for j = 1 : options.Nj
            X = [X idios(options.Nj+1-j:end-j,:)];
        end
        rhoQ( i , : ) = inv(X'*X)*X'*y;
        resids = y - X * rhoQ(  i , :)';
        %omegaQ(i,1) = var(resids) ; 
        omegaQ(i,1) = (3/sqrt(19))^2*var(resids); % Angelini, Banbura and Ruenstler (2013, XXX eq. YYY)
    else
        omegaQ(i,1) = (3/sqrt(19))^2*var(idios); % Angelini, Banbura and Ruenstler (2013, XXX eq. YYY)
        %omegaQ(i,1) = var(idios) ; 
    end    
end










