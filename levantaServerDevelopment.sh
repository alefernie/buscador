#! /bin/bash

redis-server > log/bitacoraScript.log &
sleep 10
soulmate-web --foreground --no-launch --redis=redis://localhost >> log/bitacoraScript.log &
rails runner "eval(File.read 'levantaBlurrily.rb')" &
rails s -p 4000
