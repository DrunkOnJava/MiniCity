#!/bin/bash

# Quick test to verify monitoring is integrated into standard commands
set -e

cd /Users/griffin/Projects/MiniCity/MiniCity

echo "Testing integrated monitoring system..."
echo "======================================="
echo ""

# Test 1: Check make targets exist
echo "Test 1: Checking Makefile targets..."
if make -n build >/dev/null 2>&1 && make -n run >/dev/null 2>&1; then
    echo "✅ Standard targets present"
else
    echo "❌ Missing standard targets"
    exit 1
fi

# Test 2: Check monitoring can be disabled
echo "Test 2: Testing monitoring control..."
if ENABLE_MONITORING=0 make -n run | grep -q "run-simple"; then
    echo "✅ Monitoring can be disabled"
else
    echo "❌ Monitoring control not working"
    exit 1
fi

# Test 3: Check monitoring is enabled by default
echo "Test 3: Testing default monitoring..."
if make -n run | grep -q "run-monitored"; then
    echo "✅ Monitoring enabled by default"
else
    echo "❌ Monitoring not enabled by default"
    exit 1
fi

# Test 4: Check diagnostic commands
echo "Test 4: Testing diagnostic commands..."
if make status >/dev/null 2>&1; then
    echo "✅ Diagnostic commands working"
else
    echo "❌ Diagnostic commands failed"
    exit 1
fi

echo ""
echo "================================"
echo "✅ All tests passed!"
echo ""
echo "The monitoring system is fully integrated."
echo "Claude Code can now use 'make run' and 'make build' normally,"
echo "and will automatically get crash detection and diagnostics."
echo ""
