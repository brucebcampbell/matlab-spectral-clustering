function [sL,Ar,K,R,st,W,rbinNhbr,selectId,sMd,newprotInfo] = buildLatentProtein(A,...
						  logpow,sizeIm,protInfo)
						  
%
% buildLatent: set up latent space, build kernels, 
%              generate transitional matrix for 
%              the low-dim space.
% buildLatentProtein: which is this file
% taking symmetry into account in building kernels
% calls to:
%   normalizeAffty.m 
%   emKernelFitNew.m
%
  %======== STEP 1: SET PARAMETERS ===========

  %=== kernel selection parameters ===
  % find an ordering on the kernels based on max height.
  % increasing this # will increase the total 
  % number of kernels selected
  MAX_HT_FRAC = 0.55;%0.5; % 0.55 as of Aug10, '04 for protein data
  % length of the intersection 
  INTERSECT_FRAC = 0.4;%0.4;
  MISS_FRAC = 0.75;
  % to threshold small probabilities. look in STEP 4 below.
  SUPP_PROB_FRAC = 0.01;
  
  %% parameter set that works: Apr 23, '03
  %MAX_HT_FRAC = 0.5;
  %INTERSECT_FRAC = 0.4;
  %MISS_FRAC = 0.75;
  %SUPP_PROB = 0.01;  
  
  %======== END SET PARAMETERS =======

  %======== STEP 2: NORMALIZE AFFINITIES AND GENERATE SIDE INFO =======
  [sA,D,sL,sM,sH] = normalizeAffty(A);
  
  %===========================================================
  %% ANALYZING SHIFTED KIRCHOFF MATRIX. REWRITING THE ARRAY SL
  % estimate the upperbound on the max eigenvalue from Gershgorin
  % circles as in the paper by ACE. however, it does not give
  % a good approximation for the higher order vectors
  % here are few attempts at fixing it. 
  % mx = max(sum(abs(sH),2)); 
  % mx = 1.2*mean(sum(abs(sH),2)); 

  mx = 0.5*mean(sum(abs(sH),2));  % works the best among these
  sL = spdiags(mx*ones(length(D),1),0,length(D),length(D)) - sH;
  
  % sL = spdiags(D,0,length(D),length(D)) - sA;
  
  %===========================================================
  
  % changed to save memory by vmb, 10-6-10 - these variables aren't even
  % used, anyway, so hardly matter and take up lots of memory
  sqrtD  = spdiags(D .^ 0.5,0,length(D),length(D)); %sparse(diag(D.^0.5));
  sqrtDinv = spdiags(D .^ -0.5,0,length(D),length(D)); %sparse(diag(D .^ -0.5));
  % stationary distribution 
  
  % stationary distribution 
  u0 = D/sum(D);
  % DIFFUSE THE MARKOV MATRIX
  sMp = sM;      
  sMd = [];
  for k = 1:logpow 
    sMp = sMp * sMp;
    if k == (logpow-1)
      sMd = sMp;
    end
    if (logpow == 1)
      sMd = sM;
    end
  end
  %sLp = sqrtDinv * sMp * sqrtD ;  % L = D^-0.5 Markov D^0.5
  %======== END NORMALIZE AFFINITIES AND GENERATE SIDE INFO ===
  
  
  %======== STEP 3: KERNEL SELECTION ===========
  %[selectId,newprotInfo] = latentKernelsProtein(D,sMp,protInfo);
  [selectId,newprotInfo] = latentKernelsSymmProtein(D,sMp,protInfo);
  
  %% Diffusion Kernels, picked from sMd, not sMp
  %  where sMd is markov diffused to logpow-1.
  %K = sMd(:, selectId(:));
  % aug 10,'03 quick hack to see if sMp will work as well
  % in fact, it does seem to work. so i will leave it this way.
  %K = sMd(:, selectId(:));
  K = sMd(:, selectId);  

  % AVOID SORTING TO RETAIN THE KERNEL SELECTION ORDER
  % sort the kernels based on the pixel locations
  %[selectId,id] = sort(selectId); % clearly wrong
  % UNCOMMENT THE NEXT TWO OPERATIONS IF SORTED IS NEEDED
  %[selectId,id] = sort(find(selectId));  
  selectId = find(selectId);
  %qqq = find(selectId); [qqs,qqi] = sort(-u0(qqq));selectId=qqq(qqi);
  % and shuffle the kernels
  %K = K(:,id);
  %size(K)
  
  
  %======== END KERNEL SELECTION =======

  %======== STEP 4: LATENT SPACE PROBABILITIES ======
  %[Ar,R,st,W,rbinNhbr] = latentProbs(K,u0);
  %[Ar,R,st,W,K] = setLatent(K,u0,1) ; % normalizes Ar by the median

  % set latent space. in particular, using kernels
  % K and the fine scale stationary distribution u0,
  % generate:
  %
  %  - responsibility matrix W 
  %  - latent space markov matrix R 
  %  - latent space stationary distribution st
  %  - latent space affinity matrix Ar.
  %
  % set small values of the markov matrix to zero using 
  % R + R', before generating the affinity matrix.
  % also scale the affinity matrix before returning.
  %
  % calls: emKernelFitNew
  %

  %%== OLD WAY
  %% W ownership matrix. last argument is display flag.
  %[st,W] = emKernelFit(u0,K,0); 
  %% latent space markov transition
  %R = W'*K; 
  %figure; plot(sum(R));
  %%== OLD WAY

  %%== NEW WAY
  [st,W,K,R,Ar] = emKernelFitNew(u0,K,0); % last value is display flag
  %%== NEW WAY

  ok = 0;
  
  if (ok)
  
    % thresholding small probabilities
    % consider: R = [a b; c d]
    % thresholding must be symmetric.  p(1->2) = b, is set to 0
    % only if p(2->1) = c, can also be set to 0.
    % hence use R + R' to come up with a Tolerance.
    % check if both p(1->2) and p(2->1) can be set to 0.
    flag  = 1;
    if (flag)
      trs = 0.001;
      % original line
      %Tol = 0.01*sum(R+R',2) * ones(1,size(R,2));
      % modified line
      Tol = trs*sum(R+R',2) * ones(1,size(R,2));
      RR  = (R + R') > 2*Tol;
      size(RR)
      % find locations where p(1->2) is 0 but not p(2->1)
      length(find(abs(RR-RR')))
      RR(find(abs(RR-RR'))) = 1;
      R = R .* RR;
      Rs = sum(R,1);
      R = R ./ (ones(size(R,1),1)*Rs) ;
      % as R is quantized, update st, the latent space
      % stationary distribution by power iteration
      for k = 1:50
	st = R*st;
      end
      %figure; plot(sum(R)); 
      %fprintf('sum(st): %f \n',sum(st));
      
      % similarly, update the ownership matrix
      W = K * diag(st);
      W = diag(sum(W,2).^-1) * W;
    end
    
    % latent space affty
    %Ar = R * diag(st);
    Ar = R .* (st*ones(1,size(R,2)));
    
    % make sure it is symmetric 
    %Ar = (Ar + Ar')/2;
    
  else
    
    %Ar = R .* (st*ones(1,size(R,2)));

    trs = SUPP_PROB_FRAC;%0.01;
    %Tol = trs*sum(R+R',2) * ones(1,size(R,2));
    %RR  = (R + R') > 2*Tol;
    Tol = trs*sum(R+R',2);
    RR = (spdiags(Tol.^-1, 0, length(Tol), length(Tol)) * (R+R')) > 2;
    % find locations where p(1->2) is 0 but not p(2->1)
    %size(RR)
    [rri,rrj,rrs] = find(abs(RR-RR'));
    %[length(xyz) max(xyz)]
    % this should do, but it stopped working when N = 512
    %RR(find(abs(RR-RR'))) = 1;
    [iii,jjj,sss] = find(RR);

    iii = [rri ; iii];
    jjj = [rrj ; jjj];
    sss = [ones(length(rrs),1) ; sss];
    %[min(iii) min(jjj) min(sss)]
    RR = sparse(iii,jjj,sss);

    %% THE FOLLOWING LINE WAS ALWAYS THERE. commented for testing.
    %Ar = Ar .* RR ;

    %% HACK ALERT. June '05 for protein data
    % make sure it is symmetric 
    %Ar = (Ar + Ar')/2;

    Dr = full(sum(Ar,1))';
    %R  = Ar .* (ones(size(Ar,1),1)*(Dr .^ -1));
    R  = Ar * spdiags(Dr .^ -1, 0, length(Dr), length(Dr));
    
    %sum(sum(R,1))

    st = Dr/ sum(Dr);
    st = st(:);
    
    % similarly, update the ownership matrix
    W = K * spdiags(st, 0, length(st), length(st));
    W = spdiags(full(sum(W,2).^-1),0, size(W,1), size(W,1)) * W;
    
  end % check ok
  
  
  % scale latent space affinities. this will not affect
  % the transition matrix.
  Ar = Ar/median(full(sum(Ar,1)));

  rbinNhbr = Ar > 0;
  rbinNhbr = rbinNhbr - ...
      spdiags(ones(size(rbinNhbr,1),1),0,size(rbinNhbr,1),size(rbinNhbr,1));
  
  %======== END LATENT SPACE PROBABILITIES ======  
   
  return;
