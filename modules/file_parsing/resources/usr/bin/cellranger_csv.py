"""
"""
import csv
import json
from pathlib import Path
from io import StringIO
from configparser import ConfigParser


def _load_json(input_file):
    with open(input_file, "r") as fin:
        return json.load(fin)


def _load_csv(input_file, section_key="libraries"):
    # load all content first:
    with open(input_file, "r") as fin:
        content = fin.read()
    
    # handle actual csv:
    if content[0] == "[":
        reader = csv.DictReader(StringIO(content))
        return {section_key: list(reader)}

    # handle sectioned csv:
    cfg = ConfigParser(allow_no_value=True)
    cfg.optionxform = str

    data = {}
    cfg.read_string(content)
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
    return data


class Config:
    def __init__(self, *, input_csv=None, input_json=None):
        self.input_csv = input_csv
        self.input_json = input_json

    def load_input(self, section_key="libraries"):
        if not (self.input_csv or self.input_json):
            raise Exception("No input provided")
        elif self.input_csv:
            self.config = _load_csv(self.input_csv, section_key)
        elif self.input_json:
            self.config = _load_json(self.input_json)
    
    def dump_json(self, output_file):
        with open(output_file, "w") as fout:
            json.dump(self.content, fout)

    def dump_multi_csv(self, output_file):
        cfg = ConfigParser()
        cfg = ConfigParser(allow_no_value=True)
        cfg.optionxform = str

        for section_name, options in self.config.items():
            if section_name == "pipeline": continue

            cfg.add_section(section_name)
            for option_name, option_value in options.items():
                cfg.set(section_name, option_name, option_value)
        
        with open(output_file, "w") as fout:
            cfg.write(fout)

    def dump_unsectioned_csv(self, output_file, section_key="libraries"):
        content = self.config[section_key]
        with open(output_file, "w") as fout:
            headers = list(content[0].keys())
            writer = csv.DictWriter(fout, fieldnames=headers)
            writer.writerows(content)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input-file", required=True, type=Path)
    parser.add_argument("-k", "--unsectioned-input-key", type=str, default="libraries")
    parser.add_argument("-o", "--output-file", required=True, type=Path)
    parser.add_argument("-u", "--unsectioned-output-key", type=str, default="libraries")
    parser.add_argument("-t", "--output-type", choices=["multi", "libraries", "json"])
    args = parser.parse_args()

    input_csv, input_json = None, None
    match args.input_file.ext:
        case "csv":
            input_csv = args.input_file
        case "json":
            input_json = args.input_file
        case _:
            raise Exception(f"Input file [{args.input_file}] isn't a csv or json file!")

    config = Config(input_csv=input_csv, input_json=input_json)
    config.load_input(args.unsectioned_input_key)

    match args.output_type:
        case "multi":
            config.dump_multi_csv(args.output_file)
        case "libraries":
            config.dump_unsectioned_csv(args.output_file, args.unsectioned_output_key)
        case "json":
            config.dump_json(args.output_file)

