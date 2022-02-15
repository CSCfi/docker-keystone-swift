#!/usr/bin/env python3

import argparse
import datetime
import hashlib
import json
import os
import random

import lorem

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

    args = parser.parse_args()

    n_containers = args.containers
    n_objects = args.objects

    data = {}

    data = []
    for i in range(0, n_containers):
        objects = []
        for _ in range(0, n_objects):
            objects.append(
                {
                    "name": lorem.get_sentence(comma=(0, 0), word_range=(1, 3)) + "txt",
                    "content": lorem.get_paragraph(),
                    "meta": {
                        "usertags": lorem.get_sentence(comma=(0, 0), word_range=(1, 4))[
                            :-1
                        ].replace(" ", ";")
                    },
                }
            )
        data.append(
            {
                "name": lorem.get_sentence(comma=(0, 0), word_range=(1, 3))[:-1],
                "objects": objects,
                "meta": {
                    "usertags": lorem.get_sentence(comma=(0, 0), word_range=(1, 4))[
                        :-1
                    ].replace(" ", ";")
                },
            }
        )

    with open(f"swift_data_{args.containers}_cont_{args.objects}.json", "w") as fp:
        json.dump(data, fp, indent=2)
