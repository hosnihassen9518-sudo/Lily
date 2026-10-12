#pragma once
template<class Connect,class Authorize,class Persist,class Restore,class Clock>
bool applyWifiConfiguration(Connect connect,Authorize authorize,Persist persist,Restore restore,Clock clock) {
  if(!connect() || !authorize() || !persist()) { restore(); return false; }
  clock(); return true;
}
