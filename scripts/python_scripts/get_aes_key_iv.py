import re
import subprocess
import argparse

def parse_openssl_output(output):
    """
    Parses the output of the openssl enc command to extract the Key and IV values.

    Args:
        output (str): The output of the openssl enc command.

    Returns:
        tuple: A tuple containing the Key and IV values, or None if not found.
    """
    key_match = re.search(r"key=([0-9A-F]+)", output, re.IGNORECASE)
    iv_match = re.search(r"iv =([0-9A-F]+)", output, re.IGNORECASE)

    if key_match and iv_match:
        key = key_match.group(1)
        iv = iv_match.group(1)
        return bytes.fromhex(key), bytes.fromhex(iv)
    else:
        raise ValueError("Key or IV not found in openssl output.")

def run_openssl_command(key_file):
    """
    Runs the openssl enc command and returns the output.

    Args:
        key_file (str): The path to the key file.

    Returns:
        str: The output of the openssl enc command.
    """
    try:
        command = [
            "openssl", "enc", "-aes-256-cbc", "-kfile", key_file,
            "-md", "sha256", "-P", "-nosalt"
        ]
        process = subprocess.run(command, capture_output=True, text=True, check=True)
        return process.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error: openssl command failed: {e}")
        return None

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Parses the output of the openssl enc command to extract the Key and IV values.")
    parser.add_argument("-k", "--key_file", help="The path to the key file", required=True)

    args = parser.parse_args()

    output = run_openssl_command(args.key_file)
    # print(output)

    if output:
        try:
            result = parse_openssl_output(output)
            if result:
                key, iv = result
                with open("key-aes256.bin", "wb") as f:
                    f.write(key)
                with open("iv-aes256.bin", "wb") as f:
                    f.write(iv)
                print("Key and IV written to key-aes256.bin and iv-aes256.bin")
                print(f"Key: {key.hex()}")
                print(f"IV: {iv.hex()}")
                print(f"Key (string): {key.hex().upper()}")
                print(f"IV (string): {iv.hex().upper()}")
            else:
                print("Error: Key or IV not found in openssl output.")
        except ValueError as e:
            print(f"Error: {e}")
