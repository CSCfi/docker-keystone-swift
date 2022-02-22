#!/usr/bin/env python3

import argparse
import datetime
import hashlib
import json
import os
import random

from .generate_data import create_from_lorem

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate a JSON file with a container/object structure for importing into a swift backend for testing",
    )
    parser.add_argument(
        "--containers", type=int, default=10, help="Number of containers"
    )
    parser.add_argument(
        "--objects", type=int, default=15, help="Number of objects per container"
    )
    parser.add_argument(
        "-o", "--output", type=pathlib.Path, help="Filepath to write result to"
    )

    args = parser.parse_args()

    n_containers = args.containers
    n_objects = args.objects

    data = create_from_lorem(n_containers, n_objects)

    if (args.output):
        filename = args.output
    else: 
        filename = f"swift_data_{args.containers}_cont_{args.objects}_objs.json"
    
    with open(filename, "w") as fp:
        json.dump(data, fp, indent=2)


    print(f"Created '{filename}' with {n_containers} containers, and a total of {n_containers * n_objects} objects")
