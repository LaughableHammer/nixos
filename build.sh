#!/usr/bin/env bash

git add .
sudo nixos-rebuild switch --flake .
