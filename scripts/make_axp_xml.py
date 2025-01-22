#!/usr/bin/env python3

import json
import xml.etree.ElementTree as ET

# assigns a JSON string to a variable called jess
jess = '{"name": "Jessica Wilkins", "hobbies": ["music", "watching TV", "hanging out with friends"]}'

# parses the data and assigns it to a variable called jess_dict
jess_dict = json.loads(jess)

# Printed output: {"name": "Jessica Wilkins", "hobbies": ["music", "watching TV", "hanging out with friends"]}
print(json.dumps(jess_dict, indent=4))

print(jess_dict["name"])
print(jess_dict["hobbies"])


root = ET.Element("root")
child1 = ET.SubElement(root, "child1")
child1.text = "这是child1的文本内容"
child2 = ET.SubElement(root, "child2")
child2.text = "这是child2的文本内容"
child2.set("attribute", "value")
tree = ET.ElementTree(root)

with open("example.xml", "wb") as file:
	tree.write(file, encoding="utf-8", xml_declaration=True)