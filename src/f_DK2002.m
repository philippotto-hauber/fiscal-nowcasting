function [ alphahatstar , alphaplus, yplus ] = f_DK2002(data,T,Z,R,Q,H,a1,P1,options)

%% generate unconditional draw from state vector
alphaplus = NaN(size(T,1),size(data,2)+1);
yplus = NaN(size(data,1),size(data,2));

alphaplus(:,1) = chol(P1 + eye(size(P1,1))*1e-8)*randn(size(T,1),1) + a1; % initial values of state
cholQ = chol( Q , 'lower' ) ;
cholH = chol( H , 'lower' ) ;

for t=1:size(data,2)
    yplus(:,t) = Z*alphaplus(:,t)+ cholH * randn( size( Z , 1 ) , 1 ) ;
    alphaplus(:,t+1) = T*alphaplus(:,t)+R * cholQ * randn( size( Q , 1 ) , 1 ) ;
end

alphaplus(:,end) = [];

%% generate alphahatstar by running the Kalman filter and the disturbance smoother over the artificial data y_star = y-y_plus 
ystar = data-yplus;

% empty matrices to store v, F, K and L
v = cell(size(data,2),1);
invF = cell(size(data,2),1);
L = NaN(size(T,1),size(T,1),size(data,2));

%%%%%%
% forward recursion to get v
%%%%%%

a = a1;
P = P1;
eye_N = eye(size(data,1));
% calculate RQR'
RQR = R*Q*R';

% Kalman filter recursions

for t=1:size(data,2)
    % check for missings 
    notmissings = ~isnan(ystar(:,t));
    Wt = eye_N(notmissings,:);
    % proceed with recursions
    v{t,1} = ystar(notmissings,t) - Wt*Z*a;
    F = Wt*Z*P*(Wt*Z)' + Wt*H*Wt';
    invF{t,1} = F\eye(size(F,1));
    K = T*P*(Wt*Z)'*invF{t,1};
    L(:,:,t) = T-K*Wt*Z; 
    a = T*a + K*v{t,1};
    P = T*P*L(:,:,t)'+RQR;
end

%%%%%%
% backward recursion to get r
%%%%%%
r = NaN(size(T,1),size(data,2));
r(:,end) = zeros(size(T,1),1);

for t=size(data,2)-1:-1:1
    % check for missings 
    notmissings = ~isnan(ystar(:,t+1));
    Wt = eye_N(notmissings,:);
    r(:,t) = (Wt*Z)'*invF{t+1,1}*v{t+1,1}+L(:,:,t+1)'*r(:,t+1); 
end

% r0
notmissings = ~isnan(ystar(:,1));
Wt = eye_N(notmissings,:);
r_0 = (Wt*Z)'*invF{1,1}*v{1,1}+L(:,:,1)'*r(:,1);


% forward recursions to get smoothed state alphahatstar
alphahatstar = NaN(size(T,1),size(data,2));
alphahatstar(:,1) = a1 + P1*r_0;

for t=2:size(data,2)
    alphahatstar(:,t) = T*alphahatstar(:,t-1) + R*Q*R'*r(:,t-1);
end
