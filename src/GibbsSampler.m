function draws = GibbsSampler( X , yQ , priors , options )

    % preallocate space for draws
    if options.flag_samplemoments == 0
        draws.nowcast = NaN( 1  , options.Nreplic/options.Nthin ) ;
        if options.Nh == 3
            draws.forecast = NaN( 1 , options.Nreplic/options.Nthin ) ;
        end
    elseif options.flag_samplemoments == 1
        draws.nowcast_mean = NaN( 1  , options.Nreplic/options.Nthin ) ;
        draws.nowcast_var = NaN( 1  , options.Nreplic/options.Nthin ) ;
        if options.Nh == 3
            draws.forecast_mean = NaN( 1 , options.Nreplic/options.Nthin ) ;
            draws.forecast_var = NaN( 1 , options.Nreplic/options.Nthin ) ;
        end
    end

    draws.flag_phi_prev = NaN( 1  , options.Nreplic/options.Nthin ) ; 

    % compute effective lag length
    options.Np_eff = max( [options.Np , 5 + options.Nr / options.Ns - 1 , options.Nr/options.Ns + options.Nj ] ) ; 

    % starting values
    [phi, Sigma, lambda, omega, rho] = f_startingvalues( X, yQ , options );


    if options.priorswitch == 2
        % starting values for MG prior
        psi = ones(options.Nm + options.Nq,options.Nr);
        delta = ones(options.Nr,1);
        tau = cumprod(delta);
    elseif options.priorswitch == 4
    % starting values for HS
        hs_lam2 = ones(options.Nm+options.Nq,options.Nr);
        hs_mu = nan(options.Nn,options.Nr);
        for i=1:options.Nm+options.Nq
            for j=1:options.Nr
                hs_mu(i,j) = mean(1./gamrnd(1,1./(1+1/hs_lam2(i,j)),1,1000)); 
            end
        end
        hs_tau2 = 1 ; 
        hs_xi = mean(1./gamrnd(1,1./(1+1/hs_tau2),1,1000));
        hs_eta2 = ones(options.Nm+options.Nq,options.Nr);
        hs_z = ones(options.Nm+options.Nq,options.Nr);
    end

    % iterations
    tic
    for m = 1:options.Nreplic + options.Nburnin

        if mod(m,options.Ndisplay)==0
            disp('Number of iterations');
            disp(m);toc;
            disp('-------------------------------------------')
            disp('-------------------------------------------')
        end
        % ------------------------------------------------------------------- %
        % sample eta
        % ------------------------------------------------------------------- %

        % ---------------------------- %
        % - state space params
        [T, Z, R, Q, H] = f_statespaceparams(phi,Sigma,lambda,omega,rho,options) ;

        % ---------------------------- %
        % - DK 2002
        a1 = zeros( size( T , 1 ) , 1 ) ; % initial estimate of states...
        % ... and their covariance matrix
        P1 = eye(size(T, 1)) ;

        if options.Nj > 0     % quasi-difference monthly data
            Xstar = f_qddata( X , rho( 1 : options.Nm , : ) );
            data = [ Xstar ; yQ(:,options.Nj + 1 : end ) ]; 
        else
            data = [ X ; yQ ];
        end
        if options.flag_samplemoments == 0  
            [ alpha_hat , alphaplus, ~] = f_DK2002( data , T , Z , R , Q , H , a1 , P1 , options ) ;

            alpha = alpha_hat + alphaplus ; % random draw of state vector

        elseif options.flag_samplemoments == 1
            [alpha, aTT, PTT] = f_DK2002_twostep( data , Z , T , R , Q , H , a1 , P1 ) ;

            RQR = R * Q * R' ; 
            if options.Nh == 3
                hhs = [ 0 , 3 ] ;
                [ densmean , densvar ] = f_dens_meanvar( aTT , PTT , Z , T , RQR , hhs , options ) ;
            else 
                hhs = options.Nh ;
                [ densmean , densvar ] = f_dens_meanvar( aTT , PTT , Z , T , RQR , hhs , options ) ;
            end
        end

        % ---------------------------- %
        % - extract eta and eta lags

        eta = alpha( 1 : options.Ns , : )' ;    
        etalags = alpha( 1 : options.Ns * options.Nr/options.Ns , : )' ; 

        % ---------------------------- %
        % - compute y
        y = ( lambda(options.Nm + 1 : end , : ) * alpha( 1 : options.Nr , : ) + alpha(options.Np_eff*options.Ns +  1 :options.Np_eff*options.Ns + options.Nq  , : ) )' ; 

        % ---------------------------- %
        % - compute Xplus (Xstarplus)
        Sigdraw = mvnrnd(zeros(options.Nm,1),diag(omega(1:options.Nm)),size(eta,1))' ;
        Xtemp = Z( 1 : options.Nm , 1:options.Ns ) * eta' + Sigdraw  ;
        if options.Nj > 0
            Xstarplus = Xstar ; 
            Xstarplus( isnan( Xstarplus ) ) = Xtemp( isnan( Xstarplus ) ) ;
            Xplus = f_unqdXstarplus( X , Xstarplus , rho , options ) ;
            Xstarplus = Xstarplus' ;
            Xplus = Xplus';
        else
            Xplus = X ; 
            Xplus( isnan( Xplus ) ) = Xtemp( isnan( Xplus ) ) ;
            Xplus = Xplus' ;     
        end    

        % --------------------------------------- %
        % - mean and var of predictive density
        if options.flag_samplemoments == 1
            RQR = R * Q * R' ; 
            if options.Nh == 3
                hhs = [ 0 , 3 ] ;
                [ densmean , densvar ] = f_dens_meanvar( aTT , PTT , Z , T , RQR , hhs , options ) ;
            else 
                hhs = options.Nh ;
                [ densmean , densvar ] = f_dens_meanvar( aTT , PTT , Z , T , RQR , hhs , options ) ;
            end
        elseif options.flag_samplemoments == 0        

            % sample forecasts
            % ------------------ 
            Yqfore = NaN(length(options.Nh),options.Nq); 
            Yfore = [y; NaN(max(options.Nh),options.Nq)];    
            etafore = [eta; NaN(max(options.Nh),options.Ns)];

            % simulate eta and Y max(options.Nh)-periods ahead    
            for h = 1 : max(options.Nh)
                % update etafore_vec
                etafore_vec = []; for p = 1 : options.Np ;etafore_vec = [etafore_vec; etafore(end - max(options.Nh) + h - p,:)'];end        
                % propagate factors forward
                etafore(end-max(options.Nh)+h,:) = (phi*etafore_vec + chol(Sigma)*randn(options.Ns,1))';  
                etalag = etafore(end-max(options.Nh)+h,:);
                for s = 1 : options.Nr/options.Ns - 1
                    etalag = [etafore( end - max( options.Nh ) + h - s,:) etalag];
                end

                % compute Yplus(h,:)
                Yfore(end-max(options.Nh)+h,:) = etalag * lambda( options.Nm + 1 : end , : )' + (chol(diag(omega( options.Nm + 1 : end , 1 ))) * randn(options.Nq,1))' ; 
            end

            % extract quarterly forecasts from Yfore
            if options.Nh==3
                nowcast = [1/3 2/3 3/3 2/3 1/3] * flipud(Yfore(end-7 : end-3)) ; 
                forecast = [1/3 2/3 3/3 2/3 1/3] * flipud(Yfore(end-4 : end)) ; 
            else
                nowcast = [1/3 2/3 3/3 2/3 1/3] * flipud(Yfore(end-4 : end)) ; 
            end
        end

        % ------------------------------------------------------------------- %
        % sample lambda
        % ------------------------------------------------------------------- %

        if options.Nj > 0
            % qd y
            ystar = f_qddata( y' , rho( options.Nm + 1 : end , : ) )' ; 
            % sample lambda
            if options.priorswitch == 1
                [lambda, tauinv] = f_samplelambdaNIG([ Xstarplus( options.Nj + 1 : end , : ) ystar ],etalags,rho,lambda,omega,options,priors) ; 
            elseif options.priorswitch == 2
                [lambda, psi, tau, delta] = f_samplelambdaMG([ Xstarplus( options.Nj + 1 : end , : ) ystar ],etalags,rho,omega,psi,tau,delta,options,priors) ;
            elseif options.priorswitch == 3
                lambda = f_samplelambdaPMNM([ Xstarplus( options.Nj + 1 : end , : ) ystar ],etalags,rho,lambda,omega,options,priors) ;
            elseif options.priorswitch == 4
                [lambda, hs_lam2, hs_tau2, hs_mu, hs_xi, hs_eta2, hs_z] = f_samplelambdaHS([ Xstarplus( options.Nj + 1 : end , : ) ystar ],etalags,rho,omega,hs_lam2,hs_tau2,hs_mu,hs_xi,hs_eta2,hs_z,options,priors) ; 
            elseif options.priorswitch == 5
                 lambda = f_samplelambdaNd([ Xplus y ],etalags,rho,omega,options,priors) ;        
            end
        else
            % sample lambda
            if options.priorswitch == 1
                [lambda, ~] = f_samplelambdaNIG([ Xplus y ],etalags,rho,lambda,omega,options,priors) ;  
            elseif options.priorswitch == 2
                [lambda, psi, tau, delta] = f_samplelambdaMG([ Xplus y ],etalags,rho,omega,psi,tau,delta,options,priors) ; 
            elseif options.priorswitch == 3
                lambda = f_samplelambdaPMNM([ Xplus y ],etalags,rho,lambda,omega,options,priors) ;
            elseif options.priorswitch == 4
                 [lambda, hs_lam2, hs_tau2, hs_mu, hs_xi, hs_eta2, hs_z] = f_samplelambdaHS([ Xplus y ],etalags,rho,omega,hs_lam2,hs_tau2,hs_mu,hs_xi,hs_eta2,hs_z,options,priors) ; 
            elseif options.priorswitch == 5
                 lambda = f_samplelambdaNd([ Xplus y ],etalags,rho,omega,options,priors) ;        
            end
        end

        % ------------------------------------------------------------------- %
        % sample phi_eps and Sigma_e
        % ------------------------------------------------------------------- %

        eps = [Xplus y] - etalags*lambda'; 
        if options.Nj > 0
            [rho, e, flag_rho_prev] = f_samplerho(eps, rho, omega, options, priors); % for the time being, we only model AR-dynamics in the idiosyncratic components of the monthly vars
            omega = f_samplesigma(e, priors.Omega_v, priors.Omega_delta);
        else
            omega = f_samplesigma(eps,priors.Omega_v,priors.Omega_delta);
        end

        % ------------------------------------------------------------------- %
        % sample phi_eta
        % ------------------------------------------------------------------- %

        [ phi , flag_phi_prev ] = f_sample_phi_f( eta , phi , priors , options ) ;

        % ------------------------------------------------------------------- %
        % store draws
        % ------------------------------------------------------------------- %

        if m > options.Nburnin && mod(m - options.Nburnin,options.Nthin) == 0        
            if options.flag_samplemoments == 0
                draws.nowcast( :  , (m - options.Nburnin)/options.Nthin ) = nowcast ;
                if options.Nh == 3
                    draws.forecast( : , (m - options.Nburnin)/options.Nthin ) = forecast;
                end
            elseif options.flag_samplemoments == 1
                draws.nowcast_mean( :  , (m - options.Nburnin)/options.Nthin ) = densmean( 1 , 1 ) ;
                draws.nowcast_var( :  , (m - options.Nburnin)/options.Nthin ) = densvar( 1 , 1 ) ;
                if options.Nh == 3
                    draws.forecast_mean( : , (m - options.Nburnin)/options.Nthin ) = densmean( 1 , 2 ) ;
                    draws.forecast_var( : , (m - options.Nburnin)/options.Nthin ) = densvar( 1 , 2 ) ;
                end
            end
            draws.flag_phi_prev( :  , (m - options.Nburnin)/options.Nthin ) = flag_phi_prev ;
        end
    end 
end

% ------------------------------------------------------------------- %
% FUNCTIONS
% ------------------------------------------------------------------- %

function [T, Z, R, Q, H] = f_statespaceparams(phi,Sigma,lambda,omega,rho,options)

	% state vector is [f_t ... f_t-Np_eff eQ_t ... eQ_t-4] ...
	% ... which is of dimensions Ns * Np_eff + 5 * Nq 

	H = diag( [ omega( 1 : options.Nm , 1 ); 1e-08 * ones( options.Nq , 1 ) ] ) ; 
	Q = zeros( options.Ns + options.Nq ) ; 
	Q( 1 : options.Ns , 1 : options.Ns ) = Sigma ; 
	Q( options.Ns + 1 :  options.Ns + options.Nq, options.Ns + 1 :  options.Ns + options.Nq ) = diag( omega( options.Nm + 1 : options.Nm + options.Nq , 1 ) ) ; 

	R = [ eye( options.Ns ) zeros( options.Ns , options.Nq ) ; ...
		  zeros( options.Ns * (options.Np_eff - 1 ) , options.Ns + options.Nq ) ; ...
		  zeros( options.Nq , options.Ns ) eye( options.Nq ) ; 
		  zeros( options.Nq * 4 , options.Ns + options.Nq ) ] ;    
	if options.Nj == 0 
		T = [phi zeros( options.Ns , options.Ns * (options.Np_eff - options.Np ) + 5 * options.Nq ) ; ...
			 eye( options.Ns * (options.Np_eff - 1 ) ) zeros( options.Ns * (options.Np_eff - 1 ) , options.Ns + 5 * options.Nq ) ; ...
			 zeros( options.Nq , options.Ns * options.Np_eff + 5 * options.Nq ) ; ...  
			 zeros( 4 * options.Nq , options.Ns * options.Np_eff ) eye( 4 * options.Nq ) zeros( 4 * options.Nq , options.Nq ) ] ; 
		
	   LambdaQ = f_lambdaQ( lambda( options.Nm + 1 : end , : ) , options ) ;
		Z1  =[lambda( 1 : options.Nm , : ) zeros( options.Nm , options.Ns * (options.Np_eff - options.Nr/options.Ns ) ) zeros( options.Nm , 5 * options.Nq ) ] ; ...
		Z2 = [LambdaQ zeros( options.Nq , options.Ns * options.Np_eff - size(LambdaQ,2) ) kron( [1/3 2/3 3/3 2/3 1/3] , eye( options.Nq ) ) ] ; 
		Z = [ Z1; Z2 ] ; 
	else        
		if options.Nj > 0

			Rho_q = [];
			for j = 1 : options.Nj
				Rho_q = [Rho_q diag( rho( options.Nm + 1 : end , j ) )];
			end
		end
		 
		T1 =  [phi zeros( options.Ns , options.Ns * (options.Np_eff - options.Np ) + 5 * options.Nq ) ]; ...
		T2 = [eye( options.Ns * (options.Np_eff - 1 ) ) zeros( options.Ns * (options.Np_eff - 1 ) , options.Ns + 5 * options.Nq )] ; ...
		T3 = [zeros( options.Nq , options.Ns * options.Np_eff )  Rho_q zeros( options.Nq , (5 - options.Nj) * options.Nq ) ] ; ...  
		T4 = [zeros( 4 * options.Nq , options.Ns * options.Np_eff  ) eye( 4 * options.Nq ) zeros( 4 * options.Nq , options.Nq ) ] ; 
		T = [T1;T2;T3;T4] ; 
			
		LambdaM = zeros( options.Nm , options.Ns * ( options.Nr/options.Ns + options.Nj ) ) ;
		LambdaM( : , 1 : options.Nr ) = lambda( 1 : options.Nm , 1 : options.Nr ) ; 
		   
		for i = 1 : options.Nm
			for j = 1 : options.Nj 
				%temp = kron( [ 1 -rho( i , : ) ] , eye( options.Ns ) );             
				temp = -rho( i , j ) * lambda( i , : ) ; 
				LambdaM( i , : ) = LambdaM( i , : ) + [ zeros( 1 , j * options.Ns ) temp zeros( 1 , size( LambdaM , 2 ) - size( temp , 2 ) - j * options.Ns ) ] ;
			end
		end    
		 
	 
		LambdaQ = f_lambdaQ( lambda( options.Nm + 1 : end , : ) , options ) ;
		Z1  =[LambdaM zeros( options.Nm , options.Ns * options.Np_eff - size(LambdaM,2) )  zeros( options.Nm , 5 * options.Nq ) ] ; ...
		Z2 = [LambdaQ zeros( options.Nq , options.Ns * options.Np_eff - size(LambdaQ,2) )  kron( [1/3 2/3 3/3 2/3 1/3] , eye( options.Nq ) ) ] ; 
		Z = [ Z1; Z2 ] ; 
	end
end

function LambdaQ = f_lambdaQ( lambdaQ , options )
    LambdaQ = zeros( options.Nq , options.Ns *( 5 + options.Nr/options.Ns - 1 ) ) ;
    tempaggr_rule = [ 1/3 2/3 3/3 2/3 1/3 ] ;
    for q = 1 : length( tempaggr_rule ) 
        LambdaQtemp = tempaggr_rule( q ) * lambdaQ ; 
        LambdaQ = LambdaQ + [ zeros( options.Nq , ( q - 1 ) * options.Ns ) LambdaQtemp zeros( options.Nq ,  size(LambdaQ,2) - size(LambdaQtemp,2) - ( q - 1 ) * options.Ns ) ] ;     
    end
end

function [ densmean , densvar ] = f_dens_meanvar( aTT , PTT , Z , T , RQR , hhs , options )
	densmean = NaN( 1 , length( hhs ) ) ; 
	densvar = NaN( 1 , length( hhs ) ) ; 
	counterh = 1 ; 
	for hh = hhs
		densmean( 1 , counterh ) = Z( options.Nm + 1 , : ) * T ^ hh * aTT ; 
		tempvar =  T^hh*PTT*(T^hh)';
		for h = 1 : hh
			Th = T ^ ( h - 1 ) ; 
			tempvar = tempvar + Th * RQR * (Th)' ;
		end
		densvar( 1 , counterh ) = Z( options.Nm + 1 , : ) * tempvar * Z( options.Nm + 1 , : )' ;
		counterh = counterh + 1 ; 
	end
end

function [lambda, tauinv] = f_samplelambdaNIG(data,eta,rho,lambda_prev,omega,options,priors)

	% empty matrix to store draw
	lambda = NaN(options.Nm + options.Nq,options.Nr);

	% update tau
	ad = priors.tau_v + 0.5*(options.Nm + options.Nq); bd = priors.tau_delta + 0.5*sum(lambda_prev.^2);
	tauinv = gamrnd(ad,1./bd);

	% sample lambda
	for i=1:options.Nm + options.Nq
		
		% quasi-difference if options.Nj>0
		if options.Nj > 0
			Y = data( : , i ) ; % qd-ed outside of function
			X = f_qd_eta( eta , rho( i , : ) ) ;
		else
			Y = data( 1 : end , i );
			X = eta;
		end
		% sample lambda (Christian's code)
		Qlam = diag(tauinv) + (omega(i,1)^(-1))*(X'*X); 
		blam = (omega(i,1)^(-1))*(X'*Y);
		Llam = chol(Qlam,'lower'); zlam = normrnd(0,1,options.Nr,1);
		vlam = Llam\blam;
		mlam = Llam'\vlam; 
		ylam = Llam'\zlam;
		lambda(i,:) = (ylam + mlam)';  
	end
end

function [lambda, psi, tau, delta] = f_samplelambdaMG(data,eta,rho,omega,psi,tau,delta,options,priors)

	% sample lambda
	lambda = NaN(options.Nm + options.Nq,options.Nr);
	Plam = bsxfun(@times,psi,tau');
	for i=1:options.Nm + options.Nq
		
		% quasi-difference if options.Nj>0
		if options.Nj > 0
			Y = data( : , i ) ; % qd-ed outside of function
			X = f_qd_eta( eta , rho( i , : ) ) ;

		else
			Y = data( 1 : end , i );
			X = eta;
		end
		% sample lambda (Christian's code)
		Qlam = diag(Plam(i,:)) + (omega(i,1)^(-1))*(X'*X); 
		blam = (omega(i,1)^(-1))*(X'*Y);
		Llam = chol(Qlam,'lower'); zlam = normrnd(0,1,options.Nr,1);
		vlam = Llam\blam;
		mlam = Llam'\vlam; 
		ylam = Llam'\zlam;
		lambda(i,:) = (ylam + mlam)';  
	end


	% sample psi
	% --------------

	psi = gamrnd(priors.psi_upsilon/2 + 0.5,1./(priors.psi_upsilon/2 + bsxfun(@times,lambda.^2,tau')/2));

	% sample delta's
	% ----------------

	% delta_1
	mat = bsxfun(@times,psi,lambda.^2);
	ad = priors.delta_a1 + 0.5*options.Nt*options.Nr; 
	bd = priors.delta_b1 + 0.5*(1/delta(1))*sum(tau.*sum(mat)');

	delta(1) = gamrnd(ad,1/bd);
	tau = cumprod(delta);

	% delta_2,...,delta_R
	for r = 2:options.Nr
		ad = priors.delta_a2 + 0.5*options.Nt*(options.Nr-r+1); 
		bd = priors.delta_b2 + 0.5*(1/delta(r))*sum(tau(r:end).*sum(mat(:,r:end))');
		delta(r) = gamrnd(ad,1/bd); tau = cumprod(delta);
	end 
end

function lambda = f_samplelambdaPMNM(data,eta,rho,lambda_prev,omega,options,priors)

	% empty matrix to store draw
	lambda = NaN(options.Nm + options.Nq,options.Nr);

	for r = 1:options.Nr
		% update rho
		% ----------------------------
		r1 = priors.r0*priors.s0 + sum(lambda_prev(:,r) ~= 0,1);
		r2 = priors.r0*(1-priors.s0) + options.Nm + options.Nq - sum(lambda_prev(:,r) ~= 0,1);
		rhoPMNM = betarnd(r1,r2);
		
		% update tau
		% ----------------------------
		lam_nonzero = not(lambda_prev(:,r)==0) ; 
		ad = priors.tau_v + 0.5*sum(lam_nonzero); bd = priors.tau_delta + 0.5*sum(lambda_prev(:,r).^2);
		tau = 1./gamrnd(ad,1./bd);
		
		if options.Nj > 0
			% quasi-difference if options.Nj>0
			for i = 1 : options.Nm + options.Nq
				Y = data( : , i ) ; % qd-ed outside of function
				X = f_qd_eta( eta , rho( i , : ) ) ;  
				% compute Ystar given r
				% ---------------------------
				Ystar = Y - X(:,[1:r-1 r+1:options.Nr]) * lambda_prev(i,[1:r-1 r+1:options.Nr])';

				% compute posterior moments for all i
				% ----------------------------
				Mi(i,1)= (sum(X(:,r).^2,1)./omega(i,1)+(1/tau)).^-1;
				%mi= Mi.*squeeze(sum(Ystar.*squeeze(eta(:,r,:)),1))'./diag(Omega);
				mi(i,1)= Mi(i,1).*squeeze(sum(bsxfun(@times,Ystar,X(:,r)),1))'./omega(i,1);
			end
		else
			Y = data ; % qd-ed outside of function
			X = eta ;
			% compute Ystar given r
			% ---------------------------
			Ystar = Y - X(:,[1:r-1 r+1:options.Nr]) * lambda_prev(:,[1:r-1 r+1:options.Nr])';

			% compute posterior moments for all i
			% ----------------------------
			Mi= (sum(X(:,r).^2,1)./omega+(1/tau)).^-1;
			%mi= Mi.*squeeze(sum(Ystar.*squeeze(eta(:,r,:)),1))'./diag(Omega);
			mi= Mi.*squeeze(sum(bsxfun(@times,Ystar,X(:,r)),1))'./omega;
		end
		
		% compute posterior odds
		% ----------------------------
		logPO = f_pmultnormlog(0,0,tau) - f_pmultnormlog(zeros(options.Nm + options.Nq,1),mi,Mi) + log(rhoPMNM/(1-rhoPMNM));
		PO = min(exp(logPO)./(exp(logPO) + 1),1.0e+06/(1.0e+06 + 1)); % what does the min do???

		% draw from a uniform distribution to see whether to set lambda_j equal
		% to zero or draw from N(m_i,Mi)
		% ----------------------------
		indic_nonzero = unifrnd(0,1,options.Nm + options.Nq,1);

		drawmiMi = mvnrnd(mi,diag(Mi));
		lambda_r = zeros(options.Nm+options.Nq,1);
		lambda_r(indic_nonzero <= PO,1) = drawmiMi(indic_nonzero <= PO);
		lambda(:,r) = lambda_r;
    end
end
		
function fd = f_pmultnormlog(y,prm,prv)

	% auswerten einer multivariaten normalverteilung fuer verscheidene argumente mit verschiedenen
	% parametern - ergebnis: log des funktionswertes

	%input: 
	% beta ... spaltenvektor (1 argument)
	%      ... matrix; anzahl der spalten = verschiedene argumente; die spalten  enthalten
	%                  die argumante
	% prm ... mean - spaltenvektor
	% prv ... varianz

	%output: funktionswerte ... 1 zeile


	fln = -0.5*log(prv)-0.5*log(2*pi);
	flg = -0.5*(y-prm).^2./prv;
	fd = fln+flg;
end

function [lambda, hs_lam2, hs_tau2, hs_mu, hs_xi, hs_eta2, hs_z] = f_samplelambdaHS(data,eta,rho,omega,hs_lam2,hs_tau2,hs_mu,hs_xi,hs_eta2,hs_z,options,prior)

	NT = size(data,1);

	% sample lambda
	% ------------------    
	lambda = NaN(options.Nm+options.Nq,options.Nr);

	hslam2hstau2 = hs_lam2*hs_tau2; 
	hslam2hstau2inv = 1./hslam2hstau2; 

	for i = 1:options.Nm+options.Nq
		
		% quasi-difference if options.Nj>0
		if options.Nj > 0
			Y = data( : , i ) ; % qd-ed outside of function
			X = f_qd_eta( eta , rho( i , : ) ) ;

		else
			Y = data( 1 : end , i );
			X = eta;
		end
		

		Qlam = diag(hslam2hstau2inv(i,:)) + (omega(i,1)^(-1))*(X'*X); 
		blam = (omega(i,1)^(-1))*(X'*Y);
		Llam = chol(Qlam,'lower'); zlam = normrnd(0,1,options.Nr,1);
		vlam = Llam\blam;
		mlam = Llam'\vlam; 
		ylam = Llam'\zlam;
		lambda(i,:) = (ylam + mlam)';  
    end

    if prior.flagHSplus==0

        % -- update hs_lam2 -- %
        lambda_vec = f_vec(lambda);
        hs_mu_vec = f_vec(hs_mu);
        hs_lam2_vec = 1./gamrnd(1,1./(1./hs_mu_vec + 0.5*(lambda_vec.^2)/hs_tau2));
        hs_lam2 = reshape(hs_lam2_vec,options.Nn,options.Nr);

        % -- update hs_tau2 -- %
        NnNr = options.Nn*options.Nr;
        hs_lam2_vec = f_vec(hs_lam2);
        hs_tau2 = 1./gamrnd((NnNr+1)/2,1./(1./hs_xi + 0.5*sum((lambda_vec.^2)./hs_lam2_vec)));

        % -- update hs_xi -- %
        hs_xi = 1./gamrnd(1,1./(1+1/hs_tau2));

        % -- update hs_mu -- %
        hs_mu_vec = 1./gamrnd(1,1./(1+1./hs_lam2_vec));
        hs_mu = reshape(hs_mu_vec,options.Nn,options.Nr);

        % dummies
        hs_eta2 = nan;
        hs_z = nan;

    elseif prior.flagHSplus==1

        % -- update hs_lam2 -- %
        lambda_vec = f_vec(lambda);
        hs_mu_vec = f_vec(hs_mu);
        hs_lam2_vec = 1./gamrnd(1,1./(1./hs_mu_vec + 0.5*(lambda_vec.^2)/hs_tau2));
        hs_lam2 = reshape(hs_lam2_vec,options.Nn,options.Nr);

        % -- update hs_tau2 -- %
        NnNr = options.Nn*options.Nr;
        hs_lam2_vec = f_vec(hs_lam2);
        hs_tau2 = 1./gamrnd((NnNr+1)/2,1./(1./hs_xi + 0.5*sum((lambda_vec.^2)./hs_lam2_vec)));

        % -- update hs_xi -- %
        hs_xi = 1./gamrnd(1,1./(1+1/hs_tau2));

        % -- update hs_mu -- %
        hs_eta2_vec=f_vec(hs_eta2);
        hs_mu_vec = 1./gamrnd(1,1./(1./hs_eta2_vec+1./hs_lam2_vec));
        hs_mu = reshape(hs_mu_vec,options.Nn,options.Nr);

        % -- update hs_eta2 -- %
        hs_z_vec=f_vec(hs_z);
        hs_eta2_vec = 1./gamrnd(1,1./(1./hs_mu_vec+1./hs_z_vec));
        hs_eta2 = reshape(hs_eta2_vec,options.Nn,options.Nr);

        % -- update hs_z -- %
        hs_z_vec = 1./gamrnd(1,1./(1+1./hs_eta2_vec));
        hs_z = reshape(hs_z_vec,options.Nn,options.Nr);
    end
end

function x = f_vec(X)
    %
    %
    [m, n] = size(X);
    x = reshape(X,m*n,1);
end

function lambda = f_samplelambdaNd(data,eta,rho,omega,options,priors)

	% empty matrix to store draw
	lambda = NaN(options.Nm + options.Nq,options.Nr);

	% sample lambda
	for i=1:options.Nm + options.Nq
		
		% quasi-difference if options.Nj>0
		if options.Nj > 0
			Y = data( : , i ) ; % qd-ed outside of function
			X = f_qd_eta( eta , rho( i , : ) ) ;
		else
			Y = data( 1 : end , i );
			X = eta;
		end
		% sample lambda (Christian's code)
		Qlam = diag(priors.lambdaP) + (omega(i,1)^(-1))*(X'*X); 
		blam = (omega(i,1)^(-1))*(X'*Y);
		invQlam = eye(size(Qlam, 1)) / Qlam ;
	    Llam = chol(Qlam,'lower'); zlam = normrnd(0,1,options.Nr,1);
	    vlam = Llam\blam;
	    mlam = Llam'\vlam; 
	    ylam = Llam'\zlam;
	    lambda(i,:) = (ylam + mlam)';
	end
end

function omega = f_samplesigma(resids,prior_v,prior_delta)

	[Nt,Nn] = size(resids);

	ssr = diag(resids'*resids);
	omega = 1 ./ gamrnd(prior_v + Nt/2, 1 ./(prior_delta+ssr/2)) ;
end

function [ phi_f , flag_prev_val ] = f_sample_phi_f( f , phi_f_prev , priors , options )

	% regressor and regressand
	[ y , X ] = f_constructyandX( f , options.Np ) ;

	% S_epsilon
	S_epsilon = kron( speye( options.Nt - options.Np ) , speye( options.Ns ) ) ; 

	% compute X'*S_epsilon
	XS_epsilon = X' * S_epsilon ; 

	% posterior precision of phi
	K_phi = diag(priors.phi_A) + XS_epsilon * X ; 

	% posterior mean of phi
	phi_hat = K_phi\(diag(priors.phi_A) * priors.phi_a +  XS_epsilon * y ) ;

	% random draw of phi
	max_iter = 100 ; 
	flag_prev_val = 1 ; 
	phi_f = phi_f_prev ;
	for iter = 1 : max_iter 
		phi_f_vec = phi_hat + chol( K_phi , 'lower' )' \ randn( options.Ns^2 * options.Np ,1 ) ;
		% keep draw if it satisfies stationarity
		phi_f_companion = [reshape(phi_f_vec,options.Ns*options.Np,options.Ns)';
						   eye((options.Np-1)*options.Ns) zeros((options.Np-1)*options.Ns,options.Ns)];

		if max(abs(eig(phi_f_companion))) < 1
			flag_prev_val = 0 ; 
			phi_f = reshape( phi_f_vec , options.Ns * options.Np , options.Ns )' ; % this reverses the transformation of the parameter matrix (see Chan 2017, Bayesian Macro, p. 116)
			break
		end
		
	end
end

function [ y_estim, X_estim ] = f_constructyandX( y , Np )
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % This function returns the regressand and regressors of Np-dimensional VAR
    % of the form y = X * theta + e
    %
    % INPUTS: y - Nt x Nn matrix of observations
    %         Np - lag length of VAR
    % OUTPUT: y_estim - Nn * (Nt-Np) x 1 matrix of vectorized regressands => vec([y_Np+1 ... y_Nt])
    %         X_estim - regressor matrix of dimensions Nn * (Nt-Np) x
    %         Nn^2*Np + Nn => kron( I_Nn , [1 y_t-1' ... y_t-Np'] ) stacked over Nt-Np periods
    %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % ------------------
    % - get dimensions
    % ------------------
    [Nt, Nn] = size( y ) ;

    % ------------------
    % - y_estim => vectorized y
    % ------------------

    %y_estim = reshape( y( Np + 1 : Nt , : ) , Nn * ( Nt - Np ) , 1 ) ; 
    y_estim = reshape( y( Np + 1 : Nt , : )' , Nn * ( Nt - Np ) , 1 ) ; 

    % ------------------
    % - X_estim 
    % ------------------
    X_estim = [] ; 

    for t = Np + 1 : Nt
        % X
        ylags = [] ; 
        for p = 1 : Np
            ylags = [ylags y( t - p , :  ) ] ; 
        end

       Xtemp = kron( speye( Nn ) , ylags ) ;

        X_estim = [ X_estim ;  Xtemp ] ; 
    end
end


