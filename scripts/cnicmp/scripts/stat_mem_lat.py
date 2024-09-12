import sys
import re
import numpy as np

def extract_seconds(log_line):
    match = re.search(r'memory took ([0-9.]+) seconds', log_line)
    if match:
        return float(match.group(1)) * 1000000000
    match = re.search(r'bytes took ([0-9.]+) seconds', log_line)
    if match:
        return float(match.group(1)) * 1000000000
    return None

def main(log_file_path):
    try:
        with open(log_file_path, 'r') as log_file:
            times = [extract_seconds(line) for line in log_file.readlines() if extract_seconds(line) is not None]
            
        if times:
            mean_time = np.mean(times)
            variance = np.std(times)
            print("{} entries in total".format(len(times)))
            print(f"Mean Time: {mean_time} nano seconds")
            print(f"Std: {variance} nano seconds^2")
        else:
            print("No data found in the log file.")
            
    except IOError as e:
        print(f"Could not open file: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python <script_name>.py <log_file_path>")
        sys.exit(1)

    log_file_path = sys.argv[1]
    sys.exit(main(log_file_path))
