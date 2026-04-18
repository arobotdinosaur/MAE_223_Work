% RTK GPS Visualization Script
% This script visualizes the parsed positions from RTK GPS data
% using a 3D graph representation.

% Load the parsed positions data
% Replace 'your_file.csv' with the actual file name/path
filename = 'your_file.csv';
data = readtable(filename);

% Extract the columns we need
lat_raw = data.latitude;  % Latitude in a scale 1e-7
lon_raw = data.longitude; % Longitude in a scale 1e-7
alt_raw = data.altitude_ellipsoid;  % Its in meters

% Convert to proper units
lat = lat_raw * 1e-7; % Convert latitude to degrees
lon = lon_raw * 1e-7; % Convert longitude to degrees
alt = alt_raw ; % already in meters

fprintf('Coordinate range: Lat %.8f to %.8f, Lon %.8f to %.8f\n', ...
    min(lat), max(lat), min(lon), max(lon));
fprintf('Altitude range: %.2f m to %.2f m\n', ...
    min(alt), max(alt));

% Define origin as the first point (or use mean for better centering)
origin = [lat(1), lon(1), alt(1)];
% Alternative: origin = [mean(lat), mean(lon), mean(alt)];

% Convert geographic coordinates to Local Cartesian coordinates
[xEast, yNorth, zUp] = latlon2local(lat, lon, alt, origin);

fprintf('Local Cartesian coordinate range:\n');
fprintf('  East:  %.2f to %.2f m\n', min(xEast), max(xEast));
fprintf('  North: %.2f to %.2f m\n', min(yNorth), max(yNorth));
fprintf('  Up:    %.2f to %.2f m\n', min(zUp), max(zUp));

% Create time based plots
time_data = datetime(data.year, data.month, data.day, ...
                     data.hour, data.minute, data.second);

% Extract fix type for coloring
fix_type = data.fix_type;

% Create color array based on fix_type
% Green for fix_type >= 3, Yellow for fix_type < 3
colors = zeros(length(fix_type), 3);
for i = 1:length(fix_type)
    if fix_type(i) >= 3
        colors(i, :) = [0, 0.8, 0]; % Green
    else
        colors(i, :) = [1, 0.8, 0]; % Yellow
    end
end

% Create time as numeric for 3D plotting
time_numeric = datenum(time_data);
time_height = (time_numeric - time_numeric(1)) * 24 * 3600; % Seconds from start

% Create plots
figure('Position', [100, 100, 1200, 800]);

% Plot 1: Movement path in 2D
subplot(2,2,1);
hold on;
for i = 1:length(xEast)-1
    plot([xEast(i), xEast(i+1)], [yNorth(i), yNorth(i+1)], ...
    'Color', colors(i, :), 'LineWidth', 2);
end

% Start and end markers
plot(xEast(1), yNorth(1), 'go', 'MarkerSize', 10, 'MarkerFaceColor', 'green');
plot(xEast(end), yNorth(end), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'red');
grid on;
xlabel('East-West Distance (meters)');
ylabel('North-South Distance (meters)');
title('GPS Movement Path');
% Create legend
h1 = plot(nan, nan, 'Color', [0, 0.8, 0], 'LineWidth', 2);
h2 = plot(nan, nan, 'Color', [1, 0.8, 0], 'LineWidth', 2);
legend([h1, h2], 'RTK Float/Fixed (fix ≥ 3)', 'DGPS/GPS (fix < 3)', 'Location', 'best');
axis equal;
hold off;

% Plot 2: Altitude over time
subplot(2,2,2);
hold on;
for i = 1:length(time_data)-1
    plot([time_data(i), time_data(i+1)], [xEast(i), xEast(i+1)], ...
    'Color', colors(i, :), 'LineWidth', 1.5);
end
grid on;
xlabel('Time');
ylabel('East-West Distance (meters)');
title('East-West Distance over Time');
xtickangle(45);
hold off;

% Plot 3: Position v Time (North coordinates)
subplot(2,2,3);
hold on;
for i = 1:length(time_data)-1
    plot([time_data(i), time_data(i+1)], [yNorth(i), yNorth(i+1)], ...
    'Color', colors(i, :), 'LineWidth', 1.5);
end
grid on;
xlabel('Time');
ylabel('North-South Position (meters)');
title('North-South Movement over Time');
xtickangle(45);
hold off;

% Plot 4: 3D plot with time as height
subplot(2,2,4);
hold on;
for i = 1:length(xEast)-1
    plot3([xEast(i), xEast(i+1)], [yNorth(i), yNorth(i+1)], ...
    [time_height(i), time_height(i+1)], ...
    'Color', colors(i, :), 'LineWidth', 2);
end
% Start and end markers
plot3(xEast(1), yNorth(1), time_height(1), 'go', 'MarkerSize', 8, 'MarkerFaceColor', 'green');
plot3(xEast(end), yNorth(end), time_height(end), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'red');
grid on;
xlabel('East-West (meters)');
ylabel('North-South (meters)');
zlabel('Time (seconds from start)');
title('3D GPS Movement (x, Y, Time)');
view(45, 30);
hold off;

% Print fix type statistics
fprintf('\nFix Type Statistics:\n');
fprintf('  Fix Type >= 3: %d points (%.1f%%)\n', ...
    sum(fix_type >= 3), 100*sum(fix_type >= 3)/length(fix_type));
fprintf('  Fix Type < 3: %d points (%.1f%%)\n', ...
    sum(fix_type < 3), 100*sum(fix_type < 3)/length(fix_type));
