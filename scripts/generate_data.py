#!/usr/bin/env python3

import argparse
import datetime
import hashlib
import io
import json
import os
import pathlib
import random
import socket
import time
from urllib.parse import quote

import lorem
import requests

keystone_url_template = "http://{host}:{port}/v3".format
swift_url_template = "http://{host}:{port}/auth/v1.0".format

def build_path(*parts: str) -> str:
    return "/" + "/".join(quote(part, safe="") for part in parts)


def wait_for_port(url, timeout=5.0, verbose=False, quiet=False):
    start_time = time.perf_counter()

    while True:
        try:
            r = requests.head(url)
            if verbose and not quiet:
                print()
                print(f"{url} seems to be accepting connections")
            break
        except Exception as ex:
            current = time.perf_counter() - start_time
            print(f"Waiting for {url} {current:.2f}s elapsed", end="\r")
            if time.perf_counter() - start_time >= timeout:
                raise TimeoutError(
                    "Waited too long for {} to start accepting "
                    "connections.".format(url)
                ) from ex
            time.sleep(1)
    end = time.perf_counter() - start_time
    if end > 1 and not quiet:
        print(f"Waited {end} for {url}", end="\r")
        print()


def get_tempauth_token(
    host="localhost", port=8080, username="test:tester", password="testing"
) -> str:
    auth = requests.get(
        swift_url_template(host, port),
        headers={
            "X-Storage-User": username,
            "X-Storage-Pass": password,
        },
    )
    swift_url = auth.headers["X-Storage-Url"]
    token = auth.headers["X-Auth-Token"]
    return swift_url, token


def get_keystone_token(
    host="localhost",
    port=5000,
    username="swift",
    password="veryfast",
    project="service",
) -> str:
    keystone_url = keystone_url_template(host=host, port=port)

    auth_data = {
        "auth": {
            "identity": {
                "methods": ["password"],
                "password": {
                    "user": {
                        "domain": {"id": "default"},
                        "name": username,
                        "password": password,
                    }
                },
            },
            "scope": {"project": {"name": project, "domain": {"id": "default"}}},
        }
    }

    auth = requests.request("POST", f"{keystone_url}/auth/tokens", json=auth_data)
    result = auth.json()
    if("error" in result):
        raise Exception("Keystone auth failed: {}".format(result["error"]["message"]))
    swift_url = result["token"]["catalog"][1]["endpoints"][0]["url"]
    token = auth.headers["X-Subject-Token"]
    return swift_url, token


def get_account_obj_count(swift_url: str, token: str) -> int:
    obj_count = requests.head(
        swift_url, params={"format": "json"}, headers={"X-Auth-Token": token}
    )
    return int(obj_count.headers["X-Account-Object-Count"])


def get_all_containers_obj_count(swift_url: str, token: str) -> int:
    total = 0
    account_meta = requests.get(
        swift_url, params={"format": "json"}, headers={"X-Auth-Token": token}
    )
    for container in account_meta.json():
        container_meta = requests.get(
            swift_url + "/" + container["name"],
            params={"format": "json"},
            headers={"X-Auth-Token": token},
        )
        total += int(container_meta.headers["X-Container-Object-Count"])

    return total


def create_from_lorem(n_containers, n_objects):
    n_container_tags = 3
    n_object_tags = 4
    data = []
    container_names = set()
    while len(container_names) < n_containers:
        cont_name = lorem.get_sentence(comma=(0, 0), word_range=(1, 3))[:-1]
        container_names.add(cont_name)

    for cont_name in container_names:
        objects = []
        object_names = set()
        while len(object_names) < n_objects:
            obj_name = lorem.get_sentence(comma=(0, 0), word_range=(1, 3)) + "txt"
            object_names.add(obj_name)
        for obj_name in object_names:
            object_tags = set()
            while len(object_tags) < n_object_tags:
                object_tags.add(lorem.get_word())
            objects.append(
                {
                    "name": obj_name,
                    "content": lorem.get_paragraph(),
                    "meta": {
                        "usertags": ";".join(object_tags)
                    },
                }
            )
        container_tags = set()
        while len(container_tags) < n_container_tags:
            container_tags.add(lorem.get_word())
        data.append(
            {
                "name": cont_name,
                "objects": objects,
                "meta": {
                    "usertags": ";".join(container_tags)
                },
            }
        )
    
    return data


def populate_swift(
    swift_url: str, token: str, data: dict, subfolder="", verbose=False, quiet=False
):
    if not quiet:
        start = time.perf_counter()
        print()
        n_containers = len(data)
        n_objects = sum( (len(cont["objects"]) for cont in data) )
        print(f"Creating {n_containers} containers with {n_objects} objects in total")

    for container in data:
        container_name = container["name"]
        headers = {
            f"X-Container-Meta-{key}": item for key, item in container["meta"].items()
        }
        headers["X-Auth-Token"] = token
        r = requests.put(f"{swift_url}/{container_name}", headers=headers)
        if r.status_code not in {201, 202}:
            print(f"ERROR {r.status_code} {container_name}")
        if verbose and not quiet:
            print(f"{r.status_code} {container_name}")
        for obj in container["objects"]:
            obj_name = subfolder + obj["name"]
            headers = {
                f"X-Object-Meta-{key}": item for key, item in obj["meta"].items()
            }
            headers["X-Auth-Token"] = token
            headers["Content-Type"] = "text/plain"
            r = requests.put(
                swift_url + build_path(container_name, obj_name),
                headers=headers,
                data=obj["content"]
            )
            if r.status_code != 201:
                print(f"ERROR {r.status_code} {obj_name}")
            if verbose and not quiet:
                print(f"{r.status_code} {obj_name}")
    if not quiet:
        end = time.perf_counter() - start
        print(f"Done in {end:.2f} seconds.")


def run(
    swift_url: str,
    token: str,
    json_path=None,
    subfolder="",
    n_containers=5,
    n_objects=3,
    timeout=60,
    runs=2,
    verbose=False,
    quiet=False,
):
    for _ in range(0, runs):
        start_timeout = time.perf_counter()
        existing_objs = get_account_obj_count(swift_url, token)
        containers_obj_count = 0
        if json_path:
            with open(json_path, "r") as fp:
                data = json.load(fp)
            if not quiet:
                print(f"Populating data from {json_path}")
            n_containers = len(data)
            n_objects = len(data[0]["objects"])
        else:
            data = create_from_lorem(n_containers, n_objects)

        containers_obj_count = get_all_containers_obj_count(swift_url, token)
        populate_swift(swift_url, token, data, subfolder, verbose, quiet)

        if verbose and not quiet:
            print()
            print("Wait until metadata updates")

        expected = existing_objs + (n_objects * n_containers)

        print()
        obj = get_account_obj_count(swift_url, token)
        start = time.perf_counter()
        while True:
            obj = get_account_obj_count(swift_url, token)
            containers_obj_count = get_all_containers_obj_count(swift_url, token)
            if obj == containers_obj_count:
                break
            current = time.perf_counter() - start
            if not quiet:
                print(
                    f"Current: {obj}, expected: {expected}, started with {existing_objs}. Created {containers_obj_count - existing_objs} new objects. Waited for {current:.2f} seconds",
                    end="\r",
                )
            if time.perf_counter() - start_timeout >= timeout:
                raise TimeoutError("Waited too long for metadata to update")
            time.sleep(1)
        end = time.perf_counter() - start
        if not quiet:
            print(
                f"We got {obj} objects, expected: {expected}, started with {existing_objs}. Created {containers_obj_count - existing_objs} new objects. Done in {end:.2f} seconds", end="\r"
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate containers and objects in swift object storage, and wait for metadata to be updated.",
        epilog="By default, runs with a Swift TempAuth account. use '--keystone' to authenticate agains keystone.",
    )
    parser.add_argument(
        "--host", default="localhost", help="Target swift backend host to run against"
    )
    parser.add_argument(
        "--keystone-port",
        type=int,
        default=5000,
        help="Target keystone backend port to run against",
    )
    parser.add_argument(
        "--swift-port",
        type=int,
        default=8080,
        help="Target swift backend port to run against",
    )
    parser.add_argument(
        "--keystone",
        action="store_true",
        help="Authenticate against keystone. This option changes the default username (swift) and password (veryfast)",
    )

    parser.add_argument(
        "--username",
        default="test:tester",
        help="Defaults to a swift test username (test:tester)",
    )
    parser.add_argument(
        "--password",
        default="testing",
        help="Defaults to a swift test password (testing)",
    )
    parser.add_argument(
        "--project", default="service", help="Keystone project. Defaults to (service)"
    )

    parser.add_argument(
        "--containers", type=int, default=10, help="Number of containers to create"
    )
    parser.add_argument(
        "--objects",
        type=int,
        default=15,
        help="Number of objects per container to create",
    )

    parser.add_argument(
        "--subfolder", default="", help="Prepend object names with this value"
    )

    parser.add_argument(
        "--runs",
        type=int,
        default=1,
        help="Number of times to repeat the operations. Useful to watch and benchmark the backend",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="Maximum time to wait before data is generated and metadata is updated, for each run",
    )

    parser.add_argument(
        "--from-json",
        type=pathlib.Path,
        default=None,
        help="Generate data from a pre-existing json structure",
    )

    outtput_group = parser.add_mutually_exclusive_group()
    outtput_group.add_argument(
        "-v", "--verbose", action="store_true", help="increase output verbosity"
    )
    outtput_group.add_argument(
        "-q", "--quiet", action="store_true", help="Don't print to console"
    )

    args = parser.parse_args()

    if not args.quiet:
        total_start = time.perf_counter()

    if args.keystone:
        wait_for_port(
            keystone_url_template(host=args.host, port=args.keystone_port),
            timeout=args.timeout,
            verbose=args.verbose,
            quiet=args.quiet,
        )
        wait_for_port(
            swift_url_template(host=args.host, port=args.swift_port),
            timeout=args.timeout,
            verbose=args.verbose,
            quiet=args.quiet,
        )
        swift_url, token = get_keystone_token(
            args.host, args.keystone_port, args.username, args.password, args.project
        )
    else:
        wait_for_port(
            swift_url_template(host=args.host, port=args.swift_port),
            timeout=args.timeout,
            verbose=args.verbose,
            quiet=args.quiet,
        )
        swift_url, token = get_tempauth_token(
            args.host, args.swift_port, args.username, args.password
        )

    if args.verbose and not args.quiet:
        print(f"Got token: {token}. Swift url: {swift_url}")
        print(f"Generating data ...")

    run(
        swift_url,
        token,
        args.from_json,
        args.subfolder,
        args.containers,
        args.objects,
        args.timeout,
        args.runs,
        verbose=args.verbose,
        quiet=args.quiet,
    )

    if not args.quiet:
        total_end = time.perf_counter() - total_start
        print()
        print(f"Completed in {total_end:.2f} seconds")
