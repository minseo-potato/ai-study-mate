import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const peerNames = ['지식이', '사례이', '융합이', '탐구이'];
const brand = Color(0xFF7C5CFC);
const brandSoft = Color(0xFFF1EDFF);
const ink = Color(0xFF191A1C);
const peerTints = [Color(0xFFFFEDE4), Color(0xFFE3F7EF), Color(0xFFFDE8F0), Color(0xFFFFF4D6)];
const peerAccents = [Color(0xFFFF7A45), Color(0xFF12B886), Color(0xFFF06595), Color(0xFFF59F00)];
String peerLabel(int number) => peerNames[(number - 1) % peerNames.length];
Color peerTint(int number) => peerTints[(number - 1) % peerTints.length];
Color peerAccent(int number) => peerAccents[(number - 1) % peerAccents.length];

const wideBreakpoint = 900.0;
const chatMaxWidth = 760.0;
const mutedInk = Color(0xFF8B8F97);
const lineColor = Color(0xFFE9EAEE);
