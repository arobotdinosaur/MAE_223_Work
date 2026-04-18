% RTK GPS Data Plotting
% For plotting GPS data from the buoy project
% WARNING: FILTER IS WAY TOO AGGRESSIVE
%           USE RTK FIX ONLY
clear all
close all
clc

%% Load data
filename = 'v2_dataLog00008_parsed_positions.csv'; % change to correct file
data = readtable(filename);

% get the columns
lat = data.latitude;
lon = data.longitude;
alt = data.altitude_ellipsoid;
fix_type = data.fix_type;

% check for carrier solution (0:None, 1:Float, 2:Fix)
if ismember('carrier_solution', data.Properties.VariableNames)
    carr_soln = data.carrier_solution;
    disp('Carrier Solution Stats:')
    disp(['  No RTK: ' num2str(sum(carr_soln == 0))])
    disp(['  RTK Float: ' num2str(sum(carr_soln == 1))])
    disp(['  RTK Fix: ' num2str(sum(carr_soln == 2))])
else
    % if none found, create an array of 0s
    carr_soln = zeros(size(fix_type));
    disp('no carrier solution found')
end

%% Ask user what data to use
disp(' ')
disp('What data do you want to analyze?')
disp('  1 - RTK Fix only (best accuracy)')
disp('  2 - All data (with outlier filtering)')
choice = input('Enter choice (1 or 2): ');

if choice == 1
    % filter to RTK Fix only
    rtk_mask = carr_soln == 2;
    disp(' ')
    disp(['Filtering to RTK Fix only: ' num2str(sum(rtk_mask)) ' of ' num2str(length(carr_soln)) ' points'])
    
    % keeps only RTK fix points
    lat = lat(rtk_mask);
    lon = lon(rtk_mask);
    alt = alt(rtk_mask);
    fix_type = fix_type(rtk_mask);
    carr_soln = carr_soln(rtk_mask);
    
    % make time array with mask
    time_data = datetime(data.year(rtk_mask), data.month(rtk_mask), data.day(rtk_mask), ...
                         data.hour(rtk_mask), data.minute(rtk_mask), data.second(rtk_mask));
    
    use_rtk_only = true;
else
    % use all data
    disp(' ')
    disp('Using all data with outlier filtering')
    
    % make time array
    time_data = datetime(data.year, data.month, data.day, ...
                         data.hour, data.minute, data.second);
    
    use_rtk_only = false;
end

disp(' ')
disp('What sort of test are you doing?')
disp('1 - Stationary')
disp('2 - Buoy/Walking')
choice_2 = input('Enter choice (1 or 2): ');

if choice_2 == 1
    jump_thresh_choice = 1;
    max_speed_choice = 5;
    disp('Using stationary settings: max_speed=2 m/s, jump_thresh=0.5 m')

else
    jump_thresh_choice = 1;
    max_speed_choice = 10;
    disp('Using buoy/walking settings: max_speed=10 m/s, jump_thresh=1.0 m')
end



% display the amount of data points and start time and end time
disp(' ')
disp(['Total points: ' num2str(length(lat))])
disp(['Start: ' datestr(time_data(1))])
disp(['End: ' datestr(time_data(end))])

%% Convert to local coordinates (meters)
% use median as origin
lat0 = median(lat);
lon0 = median(lon);
alt0 = median(alt);

% conversion factors (from online)
lat0_rad = deg2rad(lat0);
m_per_deg_lat = 111132.92 - 559.82*cos(2*lat0_rad) + 1.175*cos(4*lat0_rad);
m_per_deg_lon = 111412.84*cos(lat0_rad) - 93.5*cos(3*lat0_rad);

% convert to meters
x = (lon - lon0) * m_per_deg_lon;  % east
y = (lat - lat0) * m_per_deg_lat;  % north  
z = alt - alt0;                     % up

disp(' ')
disp('Before filtering:')
disp(['  E-W spread: ' num2str((max(x)-min(x))*100, '%.1f') ' cm'])
disp(['  N-S spread: ' num2str((max(y)-min(y))*100, '%.1f') ' cm'])
disp(['  Vert spread: ' num2str((max(z)-min(z))*100, '%.1f') ' cm'])

%% Filter out bad points (only if using all data)
if use_rtk_only
    % RTK Fix data is already clean, just use it directly
    valid = true(length(x), 1);
    disp(' ')
    disp('Skipping outlier filtering (RTK Fix data is clean)')
else
    % gonna use a few different methods
    valid = true(length(x), 1);
    
    % 1. velocity filter - remove impossible speeds
    dt = seconds(diff(time_data)); % time between points
    dt(dt == 0) = 0.001;  % cant divide by zero cuz...
    
    vx = diff(x) ./ dt; % velocity in x
    vy = diff(y) ./ dt; % velocity in y
    speed = sqrt(vx.^2 + vy.^2); % horrizontal speed
    
    % depending on test determines max speed
    % stationary test: max_speed = 2
    % buoy in water: 10 m/s
    % walking around: 10 m/s
    max_speed = max_speed_choice;  % m/s
    bad_speed = speed > max_speed;
    bad_vel = [false; bad_speed] | [bad_speed; false]; % adds false at the start and at the beginning
    valid = valid & ~bad_vel; % keep only good ones
    disp(['Velocity outliers: ' num2str(sum(bad_vel))])
    
    % 2. IQR filter for each axis
    for i = 1:3
        if i == 1
            d = x;
            name = 'East';
        elseif i == 2
            d = y;
            name = 'North';
        else
            d = z;
            name = 'Up';
        end
        
        good_data = d(valid);
        q1 = prctile(good_data, 25);
        q3 = prctile(good_data, 75);
        iqr_val = q3 - q1;
        
        lower = q1 - 3*iqr_val;
        upper = q3 + 3*iqr_val;
        
        bad = (d < lower) | (d > upper);
        num_bad = sum(bad & valid);
        valid = valid & ~bad;
        
        if num_bad > 0
            disp(['IQR outliers (' name '): ' num2str(num_bad)])
        end
    end
    
    % 3. jump detection
    % depending on test determines jump threshold
    % stationary test: jump_thresh = .5 m
    % buoy in water: buoy/walking/jogging = 1 m
    jump_thresh = jump_thresh_choice;  % meters
    dx = abs(diff(x));
    dy = abs(diff(y));
    jumps = sqrt(dx.^2 + dy.^2) > jump_thresh; % any jump larger than jump_thresh
    bad_jumps = [false; jumps] | [jumps; false];
    num_jumps = sum(bad_jumps & valid);
    valid = valid & ~bad_jumps;
    if num_jumps > 0
        disp(['Jump outliers: ' num2str(num_jumps)])
    end
    
    % 4. MAD filter (median absolute deviation)
    for i = 1:3
        if i == 1
            d = x;
            name = 'East';
        elseif i == 2
            d = y;
            name = 'North';
        else
            d = z;
            name = 'Up';
        end
        
        good_data = d(valid);
        med = median(good_data);
        mad_val = median(abs(good_data - med));
        thresh = 5 * mad_val * 1.4826;  % scale factor for normal dist
        
        bad = abs(d - med) > thresh;
        num_bad = sum(bad & valid);
        valid = valid & ~bad;
        
        if num_bad > 0
            disp(['MAD outliers (' name '): ' num2str(num_bad)])
        end
    end
    
    disp(' ')
    disp(['Total removed: ' num2str(sum(~valid)) ' of ' num2str(length(valid))])
    disp(['Kept: ' num2str(sum(valid)) ' points (' num2str(100*sum(valid)/length(valid), '%.1f') '%)'])
end

%% Apply filter
x_filt = x(valid);
y_filt = y(valid);
z_filt = z(valid);
time_filt = time_data(valid);
carr_filt = carr_soln(valid);
fix_filt = fix_type(valid);

disp(' ')
disp('After filtering:')
disp(['  E-W spread: ' num2str((max(x_filt)-min(x_filt))*100, '%.2f') ' cm'])
disp(['  N-S spread: ' num2str((max(y_filt)-min(y_filt))*100, '%.2f') ' cm'])
disp(['  Vert spread: ' num2str((max(z_filt)-min(z_filt))*100, '%.2f') ' cm'])

%% Calculate stats
std_x = std(x_filt);
std_y = std(y_filt);
std_z = std(z_filt);
std_horiz = sqrt(std_x^2 + std_y^2);

disp(' ')
disp('Precision (1-sigma):')
disp(['  East: ' num2str(std_x*100, '%.2f') ' cm'])
disp(['  North: ' num2str(std_y*100, '%.2f') ' cm'])
disp(['  Horizontal: ' num2str(std_horiz*100, '%.2f') ' cm'])
disp(['  Vertical: ' num2str(std_z*100, '%.2f') ' cm'])

%% Set up colors based on RTK status
colors = zeros(length(carr_filt), 3);
for i = 1:length(carr_filt)
    if carr_filt(i) == 2        % RTK Fix = bright green
        colors(i,:) = [0 0.9 0];
    elseif carr_filt(i) == 1    % RTK Float = darker green
        colors(i,:) = [0 0.5 0];
    elseif fix_filt(i) >= 3     % 3D fix = yellow
        colors(i,:) = [1 0.8 0];
    else                        % bad = red
        colors(i,:) = [1 0 0];
    end
end

% time in seconds for 3d plot
t_sec = seconds(time_filt - time_filt(1));

%% Make plots
figure('Position', [50 50 1400 850])

% plot 1 - 2D position
subplot(2,3,1)
scatter(x_filt*100, y_filt*100, 20, colors, 'filled')
hold on
plot(x_filt(1)*100, y_filt(1)*100, 'ko', 'MarkerSize', 12, 'MarkerFaceColor', 'g', 'LineWidth', 2)
plot(x_filt(end)*100, y_filt(end)*100, 'ks', 'MarkerSize', 12, 'MarkerFaceColor', 'r', 'LineWidth', 2)
% add 1-sigma circle
th = linspace(0, 2*pi, 100);
plot(mean(x_filt)*100 + std_horiz*100*cos(th), mean(y_filt)*100 + std_horiz*100*sin(th), 'b--', 'LineWidth', 1.5)
hold off
grid on
xlabel('East (cm)')
ylabel('North (cm)')
title(['GPS Position - Horiz Std: ' num2str(std_horiz*100, '%.2f') ' cm'])
axis equal
legend('Positions', 'Start', 'End', '1\sigma circle', 'Location', 'best')

% plot 2 - east vs time
subplot(2,3,2)
scatter(time_filt, x_filt*100, 12, colors, 'filled')
hold on
yline(mean(x_filt)*100, 'b-', 'LineWidth', 1.5)
yline(mean(x_filt)*100 + std_x*100, 'b--')
yline(mean(x_filt)*100 - std_x*100, 'b--')
hold off
grid on
xlabel('Time')
ylabel('East (cm)')
title(['East-West vs Time - Std: ' num2str(std_x*100, '%.2f') ' cm'])
xtickangle(45)

% plot 3 - north vs time  
subplot(2,3,3)
scatter(time_filt, y_filt*100, 12, colors, 'filled')
hold on
yline(mean(y_filt)*100, 'b-', 'LineWidth', 1.5)
yline(mean(y_filt)*100 + std_y*100, 'b--')
yline(mean(y_filt)*100 - std_y*100, 'b--')
hold off
grid on
xlabel('Time')
ylabel('North (cm)')
title(['North-South vs Time - Std: ' num2str(std_y*100, '%.2f') ' cm'])
xtickangle(45)

% plot 4 - altitude vs time
subplot(2,3,4)
scatter(time_filt, z_filt*100, 12, colors, 'filled')
hold on
yline(mean(z_filt)*100, 'b-', 'LineWidth', 1.5)
hold off
grid on
xlabel('Time')
ylabel('Altitude (cm)')
title(['Vertical vs Time - Std: ' num2str(std_z*100, '%.2f') ' cm'])
xtickangle(45)

% plot 5 - 3D trajectory
subplot(2,3,5)
scatter3(x_filt*100, y_filt*100, t_sec, 20, colors, 'filled')
hold on
plot3(x_filt(1)*100, y_filt(1)*100, t_sec(1), 'ko', 'MarkerSize', 10, 'MarkerFaceColor', 'g')
plot3(x_filt(end)*100, y_filt(end)*100, t_sec(end), 'ks', 'MarkerSize', 10, 'MarkerFaceColor', 'r')
hold off
grid on
xlabel('East (cm)')
ylabel('North (cm)')
zlabel('Time (s)')
title('3D Trajectory')
view(45, 30)

% plot 6 - histogram
subplot(2,3,6)
dist = sqrt(x_filt.^2 + y_filt.^2) * 100;
histogram(dist, 30, 'FaceColor', [0.3 0.7 0.3])
hold on
xline(std_horiz*100, 'r--', '1\sigma', 'LineWidth', 2)
xline(2*std_horiz*100, 'r:', '2\sigma', 'LineWidth', 1.5)
hold off
grid on
xlabel('Distance from Mean (cm)')
ylabel('Count')
title('Position Distribution')

% main title
if use_rtk_only
    mode_str = 'RTK Fix Only';
else
    mode_str = 'All Data (filtered)';
end

if choice_2 == 1
    test_str = 'Stationary';
else
    test_str = 'Buoy/Walking';
end

sgtitle([filename ' - ' mode_str ' - ' test_str ...
    newline 'Duration: ' num2str(minutes(time_filt(end)-time_filt(1)), '%.1f') ...
    ' min, ' num2str(length(x_filt)) ' points, Horiz Std: ' num2str(std_horiz*100, '%.2f') ' cm'], ...
    'FontSize', 12, 'FontWeight', 'bold')

%% Print summary
disp(' ')
disp('=== RTK Summary ===')
disp(['RTK Fix: ' num2str(sum(carr_filt==2)) ' (' num2str(100*sum(carr_filt==2)/length(carr_filt), '%.1f') '%)'])
disp(['RTK Float: ' num2str(sum(carr_filt==1)) ' (' num2str(100*sum(carr_filt==1)/length(carr_filt), '%.1f') '%)'])
disp(['No RTK: ' num2str(sum(carr_filt==0)) ' (' num2str(100*sum(carr_filt==0)/length(carr_filt), '%.1f') '%)'])

disp(' ')
if std_horiz*100 < 5
    disp('** Excellent RTK performance! **')
elseif std_horiz*100 < 20
    disp('Good RTK Float performance')
else
    disp('Standard GPS performance')
end