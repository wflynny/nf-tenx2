import sys
import csv
import json
from io import StringIO
from configparser import ConfigParser


if __name__ == "__main__":
    cfg = ConfigParser(allow_no_value=True)
    cfg.optionxform = str

    if len(sys.argv) != 2:
        sys.exit(1)
    
    cfg.read(sys.argv[1])

    data = {}
    for section in cfg.sections():
        buffer = StringIO("\n".join(list(filter(None, cfg[section]))))
        reader = csv.DictReader(buffer)

        #data[section] = list(reader)
        # need to handle empty entries introduced by trailing commas in csv sections
        rowdata = []
        for row in reader:
            row.pop("", None)
            rowdata.append(row)
        data[section] = rowdata
    
    json.dump(data, sys.stdout)
