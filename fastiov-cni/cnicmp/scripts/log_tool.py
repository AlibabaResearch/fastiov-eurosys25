import os
import time
import argparse


def concat_logs(log_dir, log_name, do_rm=False):
    log_tmp_dir = os.path.join(log_dir, "tmp")
    filenames = list()
    logtime_filename = ""
    print(f"\tconcatenating {log_name} logs in {log_tmp_dir}")
    for filename in os.listdir(log_tmp_dir):
        full_filename = os.path.join(log_tmp_dir, filename)
        if os.path.isfile(full_filename):
            # print(full_filename)
            if filename.startswith(log_name) and filename.endswith(".tf"):
                # print("\t\t-> log time")
                logtime_filename = filename
            elif filename.startswith("cnicmp-") and filename.endswith(".log"):
                # print("\t\t-> log data")
                filenames.append(full_filename)

    if logtime_filename == "":
        print(f"\tcannot find log time file, exit...")
        return "-1"

    if len(filenames) == 0:
        print(f"\tcannot find any log file, exit...")
        return "-1"
    
    log_time_str = logtime_filename.split("-")[-1].split(".")[0]
    log_filename = os.path.join(log_dir, f"{log_name}-{log_time_str}.log")
    if os.path.exists(log_filename):
        os.system(f"rm {log_filename}")

    os.system(f"touch {log_filename}")
    for filename in filenames:
        os.system(f"cat {filename} >> {log_filename}")

    if do_rm:
        os.system(f"rm {os.path.join(log_tmp_dir, '*')}")

    print(f"\tconcatenating {len(filenames)} log files to {log_filename}, ok!")
    return log_time_str


def main(do_rm: bool):
    print("concatenating cnicmp log files...")
    time.sleep(1)
    cur_dir_path = os.path.dirname(os.path.abspath(__file__))
    log_path = f"{cur_dir_path}/../logs"
    print(concat_logs(f"{log_path}/containerd_logs", "containerd", do_rm=do_rm))
    print(concat_logs(f"{log_path}/kata_logs", "kata", do_rm=do_rm))
    print(concat_logs(f"{log_path}/cni_logs", "cni", do_rm=do_rm))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='help')
    parser.add_argument('--rm', action='store_true', default=False, help='Boolean argument')
    args = parser.parse_args()
    main(do_rm=args.rm)
