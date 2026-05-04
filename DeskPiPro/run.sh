#!/usr/bin/with-contenv bashio

##make everything into a float
mkfloat(){
  str=$1
  if [[ $str != *"."* ]]; then
    str=$str".0"
  fi
  echo $str;
}

## Float comparison so that we don't need to call non-bash processes
fcomp() {
  local oldIFS="$IFS" op=$2 x y digitx digity
  IFS='.' x=( ${1##+([0]|[-]|[+])}) y=( ${3##+([0]|[-]|[+])}) IFS="$oldIFS"
  while [[ "${x[1]}${y[1]}" =~ [^0] ]]; do
      digitx=${x[1]:0:1} digity=${y[1]:0:1}
      (( x[0] = x[0] * 10 + ${digitx:-0} , y[0] = y[0] * 10 + ${digity:-0} ))
      x[1]=${x[1]:1} y[1]=${y[1]:1} 
  done
  [[ ${1:0:1} == '-' ]] && (( x[0] *= -1 ))
  [[ ${3:0:1} == '-' ]] && (( y[0] *= -1 ))
  (( ${x:-0} $op ${y:-0} ))
} 

CorF=$(cat options.json |jq -r '.CorF')
t1=$(mkfloat $(cat options.json |jq -r '.LowRange'))
t2=$(mkfloat $(cat options.json |jq -r '.MediumRange'))
t3=$(mkfloat $(cat options.json |jq -r '.HighRange'))
quiet=$(cat options.json |jq -r '.QuietProfile')
serialDevice=$(cat options.json |jq -r '.SerialDevice')

lastPosition=0
curPosition=-1
cpuTemp=0

STATUS_FILE=/tmp/deskpi_status
echo "Fan: 0% | Temp: 0°C" > $STATUS_FILE

ingress(){
  while true; do
    printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<html><body><p>%s</p></body></html>\r\n' \
      "$(cat $STATUS_FILE 2>/dev/null)" | nc -l -p 8099
  done
}

if [ ! -e $serialDevice ]; then
  echo "could not find $serialDevice. This addon cannot continue without a serial device. Here is a list of possible SerialDevice:";
  echo $(ls /dev/ttyUSB*)
  exit 1;
fi

ingress &
until false; do
  read cpuRawTemp</sys/class/thermal/thermal_zone0/temp
  cpuTemp=$(( $cpuRawTemp/1000 ))
  unit="C"
  if [ $CorF == "F" ]; then
    cpuTemp=$(( ( $cpuTemp *  9/5 ) + 32 ));
    unit="F"
  fi
  value=$(mkfloat $cpuTemp)
  echo "Current Temperature $cpuTemp °$unit"
  if ( fcomp $value '<=' $t1 ); then
    curPosition=1;
  elif ( fcomp $t1 '<=' $value && fcomp $value '<=' $t2 ); then
    curPosition=2;
  elif ( fcomp $t2 '<=' $value && fcomp $value '<=' $t3 ); then
    curPosition=3;
  else
    curPosition=4;
  fi
  if [ $lastPosition != $curPosition ]; then
    case $curPosition in
    1)
      echo "Level 1 - Fan 0% (OFF)";
      echo -ne "pwm_000">$serialDevice
      echo "Fan: 0% | Temp: ${cpuTemp}°${unit}" > $STATUS_FILE
    ;;
    2)
      if [ $quiet != true ]; then
        echo "Level 2 - Fan 33% (Low)";
        echo -ne "pwm_033">$serialDevice
        echo "Fan: 33% | Temp: ${cpuTemp}°${unit}" > $STATUS_FILE
      else
        echo "Quiet Level 2 - Fan 20% (Low)";
        echo -ne "pwm_020">$serialDevice
        echo "Fan: 20% | Temp: ${cpuTemp}°${unit}" > $STATUS_FILE
      fi
      ;;
    3)
      if [ $quiet != true ]; then
        echo "Level 3 - Fan 66% (Medium)";
        echo -ne "pwm_066">$serialDevice
        echo "Fan: 66% | Temp: ${cpuTemp}°${unit}" > $STATUS_FILE
      else
        echo "Quiet Level 3 - Fan 50% (Medium)";
        echo -ne "pwm_050">$serialDevice
        echo "Fan: 50% | Temp: ${cpuTemp}°${unit}" > $STATUS_FILE
      fi
      ;;
    *)
      echo "Level4 - Fan 100% (High)";
      echo -ne "pwm_100">$serialDevice
      echo "Fan: 100% | Temp: ${cpuTemp}°${unit}" > $STATUS_FILE
      ;;
    esac
    lastPosition=$curPosition;
  fi
  sleep 30;
done
