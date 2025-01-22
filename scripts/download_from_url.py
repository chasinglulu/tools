
# # 导入所需库
# import os
# import requests
# # 定义要下载的文件列表
# file_list = [
# "https://example.com/file1.txt",
# "https://example.com/file2.txt",
# "https://example.com/file3.txt",
# ]
# # 定义下载文件的函数
def download_file(url, save_path):
	response = requests.get(url)
	with open(save_path, "wb") as f:
		f.write(response.content)
	print(f"{save_path} 下载完成")
# # 遍历文件列表，逐个下载文件
# for url in file_list:
	# file_name = url.split("/")[-1]
	# save_path = os.path.join("downloads", file_name)
	# download_file(url, save_path)


import os, sys
import requests
from bs4 import BeautifulSoup

def get_file_names(url):
	response = requests.get(url)
	if response.status_code == 200:
		soup = BeautifulSoup(response.text, "html.parser")
		file_links = soup.find_all("a")
		file_names = [link.get("href") for link in file_links]
		return file_names
	else:
		return None

url = "https://iccircle.com/static/upload/"
file_names = get_file_names(url)

if not os.path.exists("downloads"):
	os.mkdir("downloads", 0o755)

if not os.path.exists("downloads/pdfs"):
	os.mkdir("downloads/pdfs", 0o755)

if not os.path.exists("downloads/pngs"):
	os.mkdir("downloads/pngs", 0o755)

if not os.path.exists("downloads/jpgs"):
	os.mkdir("downloads/jpgs", 0o755)

if not os.path.exists("downloads/zips"):
	os.mkdir("downloads/zips", 0o755)

if not os.path.exists("downloads/others"):
	os.mkdir("downloads/others", 0o755)

if file_names is not None:
	for file_name in file_names:
		print(file_name)
		if file_name.endswith("png"):
			download_file(url + file_name, "downloads/pngs/" + file_name)
		elif file_name.endswith("pdf"):
			download_file(url + file_name, "downloads/pdfs/" + file_name)
		elif file_name.endswith("jpg"):
			download_file(url + file_name, "downloads/jpgs/" + file_name)
		elif file_name.endswith("zip"):
			download_file(url + file_name, "downloads/zips/" + file_name)
		else:
			print(file_name)
			# download_file(url + file_name, "downloads/others/" + file_name)
else:
	print("获取文件名失败")
