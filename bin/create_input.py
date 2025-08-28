"""
"""
import csv
import json
from pathlib import Path
from io import StringIO
from configparser import ConfigParser


INPUT_TF_TRANSLATION = {"True": True, "False": False, "true": True, "false": False}
OUTPUT_TF_TRANSLATION = {True: "true", False: "false"}

def _load_json(input_file):
    with open(input_file, "r") as fin:
        return json.load(fin)


def _load_csv(input_file, section_key="libraries"):
    # load all content first:
    with open(input_file, "r") as fin:
        content = fin.read()
    
    # handle actual csv:
    if content[0] != "[":
        reader = csv.DictReader(StringIO(content))
        return {section_key: list(reader)}

    # handle sectioned csv:
    cfg = ConfigParser(allow_no_value=True)
    cfg.optionxform = str

    data = {}
    cfg.read_string(content)
    for section in cfg.sections():
        buffer = StringIO("\n".join(list(filter(None, cfg[section]))))
        if section in ("libraries", "samples"):
            reader = csv.DictReader(buffer)

            rowdata = []
            for row in reader:
                row.pop("", None)
                rowdata.append(row)
            data[section] = rowdata
        else:
            section_data = {}
            for line in cfg[section]:
                key, value = line.strip().split(",", 1)
                value = INPUT_TF_TRANSLATION.get(value, value)
                section_data[key] = value
            data[section] = section_data

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
        if not output_file.suffix == ".json":
            raise Exception(f"Output file [{output_file}] must be a .json file!")
        with open(output_file, "w") as fout:
            json.dump(self.config, fout)

    def dump_multi_csv(self, output_file):
        content = []
        for section_name, options in self.config.items():
            if section_name == "pipeline": continue

            content.append(f"[{section_name}]")
            if isinstance(options, dict):
                for option_name, option_value in options.items():
                    content.append(f"{option_name},{OUTPUT_TF_TRANSLATION.get(option_value, option_value)}")

            elif isinstance(options, list):
                if len(options) == 0: continue
                headers = list(options[0].keys())
                writer = csv.DictWriter(StringIO(), fieldnames=headers)
                content.append(",".join(writer.fieldnames))
                for row in options:
                    row_values = [str(row.get(h, "")) for h in writer.fieldnames]
                    content.append(",".join(row_values))

            content.append("")
            
        with open(output_file, "w") as fout:
            fout.write("\n".join(content))

    def dump_unsectioned_csv(self, output_file, section_key="libraries"):
        content = self.config[section_key]
        with open(output_file, "w") as fout:
            headers = list(content[0].keys())
            writer = csv.DictWriter(fout, fieldnames=headers)
            writer.writeheader()
            writer.writerows(content)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input-file", required=True, type=Path)
    parser.add_argument("-o", "--output-file", required=True, type=Path)
    args = parser.parse_args()

    input_csv, input_json = None, None
    match args.input_file.suffix:
        case ".csv":
            input_csv = args.input_file
        case ".json":
            input_json = args.input_file
        case _:
            raise Exception(f"Input file [{args.input_file}] isn't a csv or json file!")

    config = Config(input_csv=input_csv, input_json=input_json)
    config.load_input("libraries)")
    config.dump_json(args.output_file)
