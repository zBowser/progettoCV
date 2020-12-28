imagesNumber = 20;
squareSize = 30; % 30 mm square size

%%
% load all checkerboard images

I = imread(fullfile('images', 'Image1.tif'));
[rows, cols] = size(I);
images = zeros(rows, cols, imagesNumber);

for ii=1:imagesNumber
    imageFileName = strcat('Image', string(ii), '.tif');
    images(:, :, ii) = imread(fullfile('images', imageFileName));
end

%%
% load points using code in lab1 with imageData structure array
% added board size for each image

clear imageData

for ii=1:imagesNumber
    imageFileName = fullfile('images', strcat('Image', string(ii), '.tif'));
    imageData(ii).image = imread(imageFileName);
    
    [imagePoints, boardSize] = detectCheckerboardPoints(imageData(ii).image);
    imageData(ii).XYpixels = imagePoints;
    imageData(ii).boardSize = boardSize;
end

%%
% establish correspondences, considering square size

for ii=1:imagesNumber
%    figure
%    imshow(imageData(ii).image, 'InitialMagnification', 300)
    
    clear Xmm Ymm
    for jj=1:length(imageData(ii).XYpixels)
        [row, col] = ind2sub([imageData(ii).boardSize(1) - 1, imageData(ii).boardSize(2) - 1], jj);
        Xmm = (col - 1) * squareSize;
        Ymm = (row - 1) * squareSize;
        
        imageData(ii).XYmm(jj, :) = [Xmm, Ymm];
%{        
        hndtxt = text(imageData(ii).XYpixels(jj, 1),...
            imageData(ii).XYpixels(jj, 2),...
            num2str([Xmm, Ymm]));
        set(hndtxt, 'fontsize', 14, 'color', [1 mod(row, 2) * mod(col, 2) 0]);
%}        
    end 
%    pause(1)
end

%%
% zhang method applied knowing homography
% homography estimation provided in lab1, esimate now

for ii=1:imagesNumber
    XYpixels = imageData(ii).XYpixels;
    XYmm = imageData(ii).XYmm;
    A = [];
%    b = [];
    
    for jj=1:length(XYpixels)
        
        Xpixels = XYpixels(jj, 1);
        Ypixels = XYpixels(jj, 2);
        Xmm = XYmm(jj, 1);
        Ymm = XYmm(jj, 2);
        
        m = [Xmm; Ymm; 1];
        zero = [0; 0; 0];
        A = [A; m' zero' -Xpixels*m'; zero' m' -Ypixels*m'];
%        b = [b; 0; 0];
        
    end
    
    [U, S, V] = svd(A);
    h = V(:, end);
    
    imageData(ii).H = reshape(h, [3 3])';
    
end
%%
% check if it works, superimpose rectangle
% from lab1

for ii=1:imagesNumber
    figure
    imshow(imageData(ii).image, 'InitialMagnification', 200)
    hold on
    
    width = 150;
    height = 120;
    
    topLeftCornerX = 90;
    topLeftCornerY = 60;
    
    rectLengthX = topLeftCornerX + [0 0 width width];
    rectLengthY = topLeftCornerY + [0 height height 0];
    
    homogeneous = [rectLengthX; rectLengthY; ones(1, length(rectLengthX))];
    homProjection = imageData(ii).H * homogeneous;
    
    projection = [homProjection(1, :)./homProjection(3, :);...
        homProjection(2, :)./homProjection(3, :)];
    
    projection(:, end + 1) = projection(:, 1);
    
    plot(projection(1, :), projection(2, :), 'r', 'LineWidth', 3);
    pause(1)
end

%%POINT 1
% Zhang method, obtain b vector (L2-p73)

V = [];

for ii=1:imagesNumber
    currentH = imageData(ii).H;
    
    V = [V; compute_v_ij(1, 2, currentH)';...
        (compute_v_ij(1, 1,  currentH) - compute_v_ij(2, 2, currentH))']; 
end

[U, D, S] = svd(V);
b = S(:, end);

% need to divide to have positive definite B? (defined up to scale factor)
b = b/b(6);

% now to build B matrix (L2-p73)

B = [b(1) b(2) b(4); b(2) b(3) b(5); b(4) b(5) b(6)];
L = chol(B, 'lower');
K = inv(L');

% set proper scale
K = K/K(3, 3);

% extrinsic parameters are computed for each image (L2-p73)
for ii=1:imagesNumber
    currentH = imageData(ii).H;
    lambda = 1/norm(K \ currentH(:, 1)); % using of inv discuraged by matlab
    
    r_1 = lambda * K \ currentH(:, 1);
    r_2 = lambda * K \ currentH(:, 2);
    R = [r_1, r_2, cross(r_1, r_2)];
    
    % find closest orthogonal matrix in Frobenius norm
    [U, S, V] = svd(R);
    R_orthogonal = U * V';
    
    imageData(ii).R = R;
    imageData(ii).R_orthogonal = R_orthogonal;
    imageData(ii).t = lambda * K \ currentH(:, 3);
end

%POINT 2
% compute and show reprojected points for chosen image
% compute total reprojection error
% get matrix P

imageIndex = 1;

% matrix P not working if using R_orthogonal
P = K * [imageData(imageIndex).R, imageData(imageIndex).t];

figure
imshow(imageData(imageIndex).image, 'InitialMagnification', 200)
hold on

totalReprojectionError = 0;

for jj=1:length(imageData(imageIndex).XYmm)
    
    pointSpace = [imageData(imageIndex).XYmm(jj, 1);...
        imageData(imageIndex).XYmm(jj, 2); 0; 1];
    projPointX = (P(1, :) * pointSpace) / (P(3, :) * pointSpace);
    projPointY = (P(2, :) * pointSpace) / (P(3, :) * pointSpace);
    imagePointX = imageData(imageIndex).XYpixels(jj, 1);
    imagePointY = imageData(imageIndex).XYpixels(jj, 2);

    plot(imagePointX, imagePointY, 'r+')
    plot(projPointX, projPointY, 'g+')
    
    totalReprojectionError = totalReprojectionError + (projPointX - imagePointX)^2 +...
        (projPointY - imagePointY)^2;
end


%POINT 3
%add radial distortion compensation 
%(Lecture 2, page 70) to the basic Zhang’s calibration procedure

%Given m and m' (correspondences) do the following:
% 1 - estimate P and get intrinsic parameter from P
% 2 - estimate k1 and k2
% 3 - compensate for radial distortion and get new m'(i) 
% 4 - go to the step 1 until convergence of P and k1 and k2

% We have already P = K [R | t]
% get intrinsic parameter and rd

u_0 = K(1,3);
v_0 = K(2,3);
alpha_u = K(1,1);
skew_angle = arctan(K(1,2)/alpha_u);
alpha_v = K(2,2)*sin(skew_angle);

for jj=1:length(imageData(imageIndex).XYmm)
    
    A = [];
    b = [];
    
    pointSpace = [imageData(imageIndex).XYmm(jj, 1);...
        imageData(imageIndex).XYmm(jj, 2); 0; 1];
    projPointX = (P(1, :) * pointSpace) / (P(3, :) * pointSpace); %u^
    projPointY = (P(2, :) * pointSpace) / (P(3, :) * pointSpace); %v^
    imagePointX = imageData(imageIndex).XYpixels(jj, 1); %u
    imagePointY = imageData(imageIndex).XYpixels(jj, 2); %v

    rd_2 = ((imagePointX-u_0)/alpha_u)^2 + ((imagePointY-v_0)/alpha_v)^2;
    
    A = [(imagePointX-u_0)*rd_2 (imagePointX-u_0)*rd_2*rd_2;...
        (imagePointY-v_0)*rd_2 (imagePointY-v_0)*rd_2*rd_2];
    
    b = [projPointX-imagePointX ; projPointY - imagePointY];
    
    [k1 k2] = inv(A'*A)*A'*b;
    
end

 



