classdef compactFiltersWithHoles
% Coded by: Manuel A. Diaz @ Pprime | Univ-Poitiers, 2022.
properties
    name      % Filter name
    dim       % 1d, 2d, 3d
    Size      % [Nx,Ny,Nz]
    Mask      % Boolean filter mask
    order     % Filter polynomial degree
    filter_x  % Filter in x-direction,
    filter_y  % Filter in y-direction,
    filter_z  % Filter in z-direction.
end
%
methods
    
    function obj = compactFiltersWithHoles(varargin)
    try
        if nargin~=4, error('Inputs error'); end
        obj.name = varargin{1};
        obj.Size = varargin{2};
        mask_holes = varargin{3};
        obj.order = varargin{4};
        dimension = numel(obj.Size);
        switch dimension
            case 1, obj.dim=1; Nx=obj.Size(1); Ny=1;           Nz=1;
            case 2, obj.dim=2; Nx=obj.Size(1); Ny=obj.Size(2); Nz=1;
            case 3, obj.dim=3; Nx=obj.Size(1); Ny=obj.Size(2); Nz=obj.Size(3);
        end
    catch
        disp("Usage: ");
        disp("  Object = compactFiltersWithHoles(filter_name,[Nx],mask_holes,order)");
        disp("  Object = compactFiltersWithHoles(filter_name,[Nx,Ny],mask_holes,order)");
        disp("  Object = compactFiltersWithHoles(filter_name,[Nx,Ny,Nz],mask_holes,order)");
        disp("where:")
        disp("  Schemes available: 'TaylorFilter'.");
        return;
    end
    
    % Build filter mask using the mask_holes as a starting point:
    P = obj.order/2;
    mask_filter = mask_holes;
    
    % Add Left and right boundaries to the filter mask
    mask_filter(:,   1:P   ) = true;
    mask_filter(:,Nx-P+1:Nx) = true;
    
    % Extend holes in the x-direction
    for j=1:Ny
        for i=1:Nx-1
            slope = int16(mask_holes(j,i+1))-int16(mask_holes(j,i));
            if slope < 0
                %disp('this is a left boundary')
                for idx_l = i+1:i+P
                mask_filter(j,idx_l) = true;
                end
            elseif slope > 0
                %disp('this is right boundary');
                for idx_r = i-P+1:i
                mask_filter(j,idx_r) = true;
                end
            else 
                % Do nothing !
            end
        end
    end
    
    if obj.dim==2 
    % Add Top and bottom boundaries to the filter mask
    mask_filter(   1:P   ,:) = true;
    mask_filter(Ny-P+1:Ny,:) = true;

    % Extend holes in the y-direction
    for i=1:Nx
        for j=1:Ny-1
            slope = int16(mask_holes(j+1,i))-int16(mask_holes(j,i));
            if slope < 0
                %disp('this is a left boundary')
                for jdx_l = j+1:j+P
                mask_filter(jdx_l,i) = true;
                end
            elseif slope > 0
                %disp('this is right boundary');
                for jdx_r = j-P+1:j
                mask_filter(jdx_r,i) = true;
                end
            else 
                % Do nothing !
            end
        end
    end
    %
    end
    
    % Save filtering mask
    obj.Mask = mask_filter;
    
    % Build the selected filter;
    switch obj.dim
            
        %%%%%%%%%
        case 1 
        %%%%%%%%%
        
        % Build a low-pass filter (i.e.: I - Filter_{high-pass})
        obj.filter_x = speye(Nx) - obj.buildHighPassFilter(obj.order,mask_filter,Nx);
        
        %%%%%%%%%
        case 2
        %%%%%%%%%
        
        % Build a low-pass filter
        A_lowPass(1).general = speye(Nx) - obj.buildHighPassFilter(obj.order,[],Nx);
        A_lowPass(Ny).mat = [];
        for j=1:Ny
            A_lowPass(j).mat = speye(Nx) - obj.buildHighPassFilter(obj.order,mask_filter(j,:),Nx);
        end
        
        % The filter in x-direction is:
        obj.filter_x = obj.KRON(A_lowPass,speye(Ny));
        
        % Build a low-pass filter
        B_lowPass(1).general = speye(Ny) - obj.buildHighPassFilter(obj.order,[],Ny);
        B_lowPass(Nx).mat = [];
        for i=1:Nx
            B_lowPass(i).mat = speye(Ny) - obj.buildHighPassFilter(obj.order,mask_filter(:,i),Ny);
        end
        
        % The filter in y-direction is:
        obj.filter_y = obj.KRON(speye(Nx),B_lowPass);

        %%%%%%%%
        case 3
        %%%%%%%%
        
        % Under construction ! (I'll come back to finish it later in the future M.D.)
        
        otherwise, error('Error: Filter not available.')
    end
    end % Constructor function
    
    function A_highPass = buildHighPassFilter(obj,order,mask_holes,N)
        % Define order and coeficients
        P = order/2;
        coefs = transpose(obj.TaylorFilterCoefs(order));
        
        % Define holes coeficients
        holes = zeros(size(coefs));
        %holes(P+1) = 1; % nope! (compact filters need no self-reference)
        
        % Filter matrix A
        diags = repmat(coefs,[N,1]);	% The general diagonal
        indexes = find(mask_holes);     % Find holes indexes
        if not(isempty(indexes))
            % Set Holes at indexes
            for k=1:numel(indexes)
                diags(indexes(k),:) = holes;	% Set row to a hole coefs
            end
        end
        
        % Return
        A_highPass = transpose(spdiags(diags,[-P:P],N,N));	%#ok<NBRAK>
    end
    
end % Public Methods

methods (Static)
    
    function x = TaylorFilterCoefs(order)
        % Build Taylor filter coeficients for a given order
        %
        % Example: Build 9 points filter
        % With 9 points, the filter order is expected to be O(h^8). 
        % Given symmetry, the problem simply requires to find 5 coeficients
        % from a solving the a linear system of the form A*coefs = b, where
        %
        % A=[ 1  2    2    2    2   ; ...
        %     1 -2    2   -2    2   ; ...
        %     0  1^2  2^2  3^2  4^2 ; ...
        %     0  1^4  2^4  3^4  4^4 ; ...
        %     0  1^6  2^6  3^6  4^6 ];
        %
        % b = [0,1,0,0,0]';
        %
        % So that coefs = A\B;
        %
        if(mod(order,2)~=0)
           disp('*** ERROR: order should be even ***')
           disp('*** --> STOP')
           return
        end
        %
        % Max stencil indexes [ i-N, .. ,0, .. ,i+N ]
        N=order/2;
        % Build system A*x = b
        A=zeros(N+1);
        b=zeros(N+1,1);
        % first row of matrix A(H(0)=0)
        A(1,:)=2; A(1,1)=1;
        % second row of matrix A (H(pi)=1)
        A(2,1)=1;
        for i=2:N+1
           A(2,i)=2*(-1)^(i-1);
        end
        % other rows of matrix A(higher order conditions)
        for irow=3:N+1
           for icol=2:N+1
              A(irow,icol)=(icol-1)^(2*(irow-2));
           end
        end
        % Debug Matrix A
        %disp(A)
        % Vector b
        b(2)=1;
        % Solver for coefs in vector x:
        x = A\b;
        % Arrange output coefs:
        x = [x(N+1:-1:2);x];
    end
    
    function K = KRON(A,B)
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %
    %         A pseudo-kron operator for a structured input values
    %            Coded by Manuel A. Diaz @ ENSMA | Pprime 2021
    %
    % This routine is intended for aiding on building finite-difference
    % operators with holes.
    %
    % Usage: Kron(A,B)    : A,B are matrices of size (m x n), (p x q) respec.
    %        Kron(A{p},B) : A{p} is a structure of p-matrices, B is a matrix.
    %        Kron(A,B{m}) : A is a matrix, B{m} is a structure of m-matrices. 
    %        Kron(A{p},B{m}) : A & B are each a structure of p- and m-matrices.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % 1. Evaluate type of inputs
    if     and( isstruct(A), not(isstruct(B))), operate_on = 'A';
    elseif and(not(isstruct(A)),isstruct(B)), operate_on = 'B';
    elseif and( isstruct(A), isstruct(B)), operate_on = 'AB';
    else,  operate_on = 'kron'; % because KRON == kron
    end

    % 2. Perform kron operation
    switch operate_on
    case '0' % traditional kron algorithm
        % Size of matrix A & B
        [m,n] = size(A);
        [p,q] = size(B);

        % Total number of nonzero elements
        nz = nnz(A) * nnz(B);

        % Indexes of nonzero elements
        [M,N] = find(A);
        [P,Q] = find(B);

        % Kronecker product
        K = spalloc(p*m,q*n,nz); 
        for k=1:numel(M)
            for r=1:numel(P)
                K( P(r)+p*(M(k)-1), Q(r)+q*(N(k)-1) ) = A(M(k),N(k))*B(P(r),Q(r));
            end
        end
    case 'A'  % Perform a kron(A(n),B)
        % Size of matrix A & B
        [m,n] = size(A(1).mat); nA = numel(A);
        [p,q] = size(B);
        if nA ~= p, error('KRON(A(p),B): incompatible number(p) of elements!'); end

        % Total number of nonzero elements
        nz = nnz(A(1).general) * nnz(B);

        % Indexes of nonzero elements
        [M,N] = find(A(1).general);
        [P,Q] = find(B);

        % Kronecker product
        K = spalloc(p*m,q*n,nz);
        A_coefs = zeros(nA,1);
        for k = 1:numel(M)
            for l = 1:nA
                A_coefs(l) = A(l).mat(M(k),N(k));
            end
            LHS = spdiags(A_coefs,0,nA,nA)*B;
            for r = 1:numel(P)
                K(P(r)+p*(M(k)-1),Q(r)+q*(N(k)-1))=LHS(P(r),Q(r));
            end
        end
    case 'B'  % Perform a kron(A,B(n))
        % Size of matrix A & B
        [m,n] = size(A);
        [p,q] = size(B(1).mat); nB = numel(B);
        if nB ~= m, error('KRON(A,B(m)): incompatible number(m) of elements!'); end

        % Total number of nonzero elements
        nz = nnz(A) * nnz(B(1).general);

        % Indexes of nonzero elements
        [M,N] = find(A);
        [P,Q] = find(B(1).general);

        % Kronecker product
        K = spalloc(p*m,q*n,nz);
        for k = 1:numel(M)
            LHS = A(M(k),N(k))*B(M(k)).mat;
            for r = 1:numel(P)
                K(P(r)+p*(M(k)-1),Q(r)+q*(N(k)-1))=LHS(P(r),Q(r));
            end
        end
    case 'AB' % Perform a kron(A(n),B(n))
        [m,n] = size(A(1).mat); nA = numel(A);
        [p,q] = size(B(1).mat); nB = numel(B);
        if nA ~= p, error('KRON(A(p),B(m)): incompatible number(p) of elements!'); end
        if nB ~= m, error('KRON(A(p),B(m)): incompatible number(m) of elements!'); end

        % Total number of nonzero elements
        nz = nnz(A(1).general) * nnz(B(1).general);

        % Indexes of nonzero elements
        [M,N] = find(A(1).general);
        [P,Q] = find(B(1).general);

        % Kronecker product
        K = spalloc(p*m,q*n,nz);
        A_coefs = zeros(nA,1);
        for k = 1:numel(M)
            for l = 1:nA
                A_coefs(l) = A(l).mat(M(k),N(k));
            end
            LHS = spdiags(A_coefs,0,nA,nA)*B(M(k)).mat;
            for r = 1:numel(P)
                K(P(r)+p*(M(k)-1),Q(r)+q*(N(k)-1))=LHS(P(r),Q(r));
            end
        end

    otherwise % Operate with traditional kron(A,B)
        K = kron(A,B);
    end
    %
    end % pseudo-kron function
    
end % Private Methods

end % compactFilters object ;)