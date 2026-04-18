% Simple IMU Plotting


clear; clc; close all;

%% Load data
data = readtable('imuLog00013.csv');

% extract and convert accelerometer (milli-g to m/s^2)
accX = data.AccX / 1000 * 9.81;
accY = data.AccY / 1000 * 9.81;
accZ = data.AccZ / 1000 * 9.81;

% gyroscope (already in deg/s)
gyrX = data.GyrX;
gyrY = data.GyrY;
gyrZ = data.GyrZ;

% magnetometer (already in uT)
magX = data.MagX;
magY = data.MagY;
magZ = data.MagZ;

% temperature
temp = data.Temp;

% fix timestamps
timestamps = data.Timestamp;
clean_timestamps = cellfun(@(x) strrep(x, ' IMU', ''), timestamps, 'UniformOutput', false);
time_data = datetime(clean_timestamps, 'InputFormat', 'yyyy/MM/dd HH:mm:ss.SS');
time_sec = seconds(time_data - time_data(1));

fprintf('Samples: %d\n', length(accX));
fprintf('Duration: %.1f sec\n', max(time_sec));

%% Plot everything
figure('Position', [50 50 1200 800]);

% Accelerometer
subplot(2,2,1);
plot(time_sec, accX, 'r', time_sec, accY, 'g', time_sec, accZ, 'b');
grid on; xlabel('Time (s)'); ylabel('m/s^2');
title('Accelerometer'); legend('X','Y','Z');

% Gyroscope
subplot(2,2,2);
plot(time_sec, gyrX, 'r', time_sec, gyrY, 'g', time_sec, gyrZ, 'b');
grid on; xlabel('Time (s)'); ylabel('deg/s');
title('Gyroscope'); legend('X','Y','Z');

% Magnetometer
subplot(2,2,3);
plot(time_sec, magX, 'r', time_sec, magY, 'g', time_sec, magZ, 'b');
grid on; xlabel('Time (s)'); ylabel('uT');
title('Magnetometer'); legend('X','Y','Z');

% Temperature
subplot(2,2,4);
plot(time_sec, temp, 'm');
grid on; xlabel('Time (s)'); ylabel('C');
title('Temperature');

fprintf('Done!\n');