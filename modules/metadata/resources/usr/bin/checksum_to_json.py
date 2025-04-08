import sys
import json


def hash2json(hashfile, jsonfile):
    data = []
    with open(hashfile, "r") as fin:
        for line in fin:
            hash, filename = line.strip().split()
            data.append({"filename": filename, "checksum": hash})

    with open(jsonfile, "w") as fout:
        json.dump(data, fout)


def json2hash(jsonfile, hashfile):
    with open(jsonfile, "r") as fin:
        data = json.load(fin)

    with open(hashfile, "w") as fout:
        for obj in data:
            fout.write(f"{obj['checksum']} {obj['filename']}") 


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Supply inputfile and outputfile")
        sys.exit()
    
    try:
        hash2json(sys.argv[1], sys.argv[2])
    except Exception as e:
        print(f"Cannot convert {sys.argv[1]} to {sys.argv[2]}")
        raise e
