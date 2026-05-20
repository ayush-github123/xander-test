#!/bin/bash
# Context Layer - Complete Build & Run Guide

set -e

echo "============================================================"
echo "Xander Context Layer - Build & Run Guide"
echo "============================================================"
echo ""

PROJECT_DIR="/home/ayushrai/Documents/xander"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Check prerequisites
check_prerequisites() {
    echo ""
    echo "Checking prerequisites..."
    
    if ! command -v go &> /dev/null; then
        warn "Go not found - required for context-engine"
        return 1
    fi
    success "Go installed: $(go version | awk '{print $3}')"
    
    if ! command -v python3 &> /dev/null; then
        warn "Python3 not found - required for agent"
        return 1
    fi
    success "Python3 installed: $(python3 --version | awk '{print $2}')"
    
    return 0
}

# Build components
build_aggregation_engine() {
    echo ""
    echo "Step 1: Building Aggregation Engine..."
    
    cd "$PROJECT_DIR/aggregation-engine"
    
    if [ ! -f "bin/aggregation-engine" ]; then
        make build
        success "Aggregation Engine built"
    else
        success "Aggregation Engine already built"
    fi
}

build_context_engine() {
    echo ""
    echo "Step 2: Building Context Engine..."
    
    cd "$PROJECT_DIR/context-engine"
    
    # Initialize go module if needed
    if [ ! -f "go.sum" ]; then
        go mod tidy
    fi
    
    make build
    success "Context Engine built"
}

# Generate data
generate_aggregates() {
    echo ""
    echo "Step 3: Generating Aggregates..."
    
    cd "$PROJECT_DIR/aggregation-engine"
    
    if [ ! -f "aggregates_1m.json" ]; then
        warn "aggregates_1m.json not found - skipping generation"
        warn "To generate: cd aggregation-engine && ./bin/aggregation-engine -window 1m"
        return 1
    else
        success "aggregates_1m.json found ($(stat -f%z aggregates_1m.json 2>/dev/null || stat -c%s aggregates_1m.json 2>/dev/null || echo "?") bytes)"
    fi
    
    return 0
}

generate_context() {
    echo ""
    echo "Step 4: Generating Context..."
    
    cd "$PROJECT_DIR/context-engine"
    
    if [ ! -f "../aggregation-engine/aggregates_1m.json" ]; then
        warn "aggregates_1m.json not found - cannot generate context"
        return 1
    fi
    
    # Run context engine
    ./bin/context-engine \
        -aggregates ../aggregation-engine/aggregates_1m.json \
        -output ./context-output
    
    # Check output
    LATEST_CONTEXT=$(ls -t context-output/context_*.json 2>/dev/null | head -1)
    if [ -n "$LATEST_CONTEXT" ]; then
        success "Context generated: $(basename $LATEST_CONTEXT)"
        success "Size: $(stat -f%z $LATEST_CONTEXT 2>/dev/null || stat -c%s $LATEST_CONTEXT 2>/dev/null || echo "?") bytes"
    else
        warn "Failed to generate context"
        return 1
    fi
    
    return 0
}

# Test components
test_context_service() {
    echo ""
    echo "Step 5: Testing Context Service..."
    
    cd "$PROJECT_DIR"
    
    python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')

try:
    from agent.context_service import ContextService
    
    service = ContextService(context_dir="./context-engine/context-output")
    context = service.load_latest_context()
    
    if context:
        summary = service.get_system_health_summary()
        print(f"✓ Context loaded successfully")
        print(f"  Timestamp: {summary['timestamp']}")
        print(f"  Total Containers: {summary['total_containers']}")
        print(f"  Containers at Risk: {summary['containers_at_risk']}")
        print(f"  Available query methods: 16+")
    else:
        print("✗ Failed to load context")
        sys.exit(1)
except Exception as e:
    print(f"✗ Error: {e}")
    sys.exit(1)
PYEOF
}

# Run example agent
run_example_agent() {
    echo ""
    echo "Step 6: Running Example Agent..."
    
    cd "$PROJECT_DIR"
    
    python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')

try:
    from agent.context_service import ContextService
    
    service = ContextService(context_dir="./context-engine/context-output")
    context = service.load_latest_context()
    
    if context:
        print("\n" + "="*60)
        print("AGENT ANALYSIS RESULTS")
        print("="*60)
        
        summary = service.get_system_health_summary()
        print(f"\nSystem Status:")
        print(f"  Timestamp: {summary['timestamp']}")
        print(f"  Total Containers: {summary['total_containers']}")
        print(f"  Containers at Risk: {summary['containers_at_risk']}")
        print(f"  Critical Anomalies: {summary['critical_anomalies']}")
        
        insights = service.get_actionable_insights()
        print(f"\nActionable Insights:")
        has_insights = False
        for category, items in insights.items():
            if items:
                has_insights = True
                print(f"  {category.upper()}:")
                for item in items:
                    print(f"    • {item}")
        
        if not has_insights:
            print("  ✓ No immediate actions required - system operating normally")
        
        print("\n" + "="*60)
        print("✓ Agent ready for deployment")
        print("="*60 + "\n")
        
except Exception as e:
    print(f"✗ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF
}

# Print usage info
print_usage() {
    echo ""
    echo "============================================================"
    echo "Usage Information"
    echo "============================================================"
    echo ""
    echo "Start Telemetry Collector:"
    echo "  cd $PROJECT_DIR/telemetry-collector"
    echo "  make run"
    echo ""
    echo "Generate Aggregates:"
    echo "  cd $PROJECT_DIR/aggregation-engine"
    echo "  ./bin/aggregation-engine -window 1m"
    echo ""
    echo "Generate Context:"
    echo "  cd $PROJECT_DIR/context-engine"
    echo "  ./bin/context-engine -aggregates ../aggregation-engine/aggregates_1m.json"
    echo ""
    echo "Run Agent (Python):"
    echo "  cd $PROJECT_DIR"
    echo "  python3 agent/example_agent.py"
    echo ""
    echo "Or use Context Service in your own code:"
    echo "  from agent.context_service import ContextService"
    echo "  service = ContextService()"
    echo "  context = service.load_latest_context()"
    echo ""
}

# Print next steps
print_next_steps() {
    echo ""
    echo "============================================================"
    echo "Next Steps"
    echo "============================================================"
    echo ""
    echo "1. Read Documentation:"
    echo "   → CONTEXT_LAYER.md - Complete integration guide"
    echo "   → CONTEXT_IMPLEMENTATION.md - Technical details"
    echo "   → PROJECT_STRUCTURE.md - System architecture"
    echo ""
    echo "2. Review Context Output:"
    echo "   cd context-engine/context-output"
    echo "   jq '.containers | keys' context_*.json | head -5"
    echo ""
    echo "3. Build Your Agent:"
    echo "   Use agent/example_agent.py as a template"
    echo "   See agent/context_service.py for available APIs"
    echo ""
    echo "4. Automate Context Generation:"
    echo "   Create cron job or systemd timer to run context-engine"
    echo "   Update every 1-5 minutes"
    echo ""
    echo "5. Implement Agent Actions:"
    echo "   - Container scaling (horizontal/vertical)"
    echo "   - Workload migration"
    echo "   - Resource limits adjustment"
    echo "   - Alert generation"
    echo ""
}

# Main execution
main() {
    info "Starting build and test sequence..."
    
    # Check prerequisites
    if ! check_prerequisites; then
        warn "Prerequisites check failed"
        exit 1
    fi
    
    # Build step
    build_aggregation_engine || exit 1
    build_context_engine || exit 1
    
    # Data generation
    if generate_aggregates; then
        if generate_context; then
            # Testing
            test_context_service && success "Context Service test passed"
            
            # Run agent
            run_example_agent
        fi
    else
        warn "Skipping context generation - no aggregates available"
        warn "Run aggregation engine first: cd $PROJECT_DIR/aggregation-engine && make run"
    fi
    
    print_usage
    print_next_steps
    
    echo ""
    success "Setup complete! Context layer is ready for Agent integration."
    echo ""
}

# Run main
main
