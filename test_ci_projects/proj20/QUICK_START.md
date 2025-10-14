# Quick Start Guide - proj20

## What is proj20?

**proj20** is a comprehensive "kitchen sink" test project that combines **ALL** GitLab CI features from proj1-proj19 into a single, realistic monorepo pipeline.

## 🎯 Purpose

Test GitLab CI parsers with:
- 70+ jobs across 12 stages
- 4 microservices (Node.js, Ruby, Python, Go)
- All major GitLab CI features
- Complex job dependencies (DAG)
- Realistic deployment workflow

## 📊 Quick Stats

```
Jobs:          70+
Stages:        12
Services:      4 microservices
Languages:     4 (JS, Ruby, Python, Go)
YAML Files:    5 (main + 4 includes)
Lines:         1068 (main config)
Complexity:    Production-grade monorepo
```

## 📁 Structure

```
proj20/
├── .gitlab-ci.yml              # Main pipeline (1068 lines)
├── .gitlab/ci/                 # Included configurations
│   ├── frontend.yml
│   ├── backend.yml
│   ├── security.yml
│   └── monitoring.yml
├── services/                   # 4 microservices
│   ├── frontend/              # Node.js/React
│   ├── backend/               # Ruby/Rails
│   ├── api/                   # Python/FastAPI
│   └── workers/               # Go
└── docs/                      # 5 documentation files
    ├── README.md
    ├── FEATURES.md
    ├── TESTING_GUIDE.md
    ├── PROJECT_SUMMARY.md
    └── INDEX.md
```

## 🚀 Features Demonstrated

### Basic Features
- ✅ Multiple stages (12)
- ✅ Simple scripts
- ✅ Job dependencies

### Advanced Features
- ✅ Variables (global, job, dotenv)
- ✅ Artifacts (paths, reports, dependencies)
- ✅ Services (PostgreSQL, Redis, Elasticsearch)
- ✅ Rules (branch, changes, variables)
- ✅ Cache (global, per-service, dynamic keys)
- ✅ Before/after scripts
- ✅ Includes (local files)
- ✅ YAML anchors
- ✅ Extends (templates)
- ✅ Retry & timeout
- ✅ Reports (JUnit, coverage, SAST, etc.)
- ✅ Child pipelines
- ✅ Matrix parallelization
- ✅ Resource groups
- ✅ Environments

## 📖 Documentation Files

| File | Purpose | Read First? |
|------|---------|-------------|
| **README.md** | Comprehensive overview | ⭐ Start here |
| **FEATURES.md** | Feature mapping (proj1-19) | For reference |
| **TESTING_GUIDE.md** | Parser testing guide | For testers |
| **PROJECT_SUMMARY.md** | Quick stats | For overview |
| **INDEX.md** | Complete file listing | For navigation |
| **QUICK_START.md** | This file | For quick intro |

## 🔍 Key Test Scenarios

### Scenario 1: Parse Pipeline
```bash
# Test basic parsing
gitlab-ci-local --list
# Expected: 70+ jobs listed
```

### Scenario 2: Check DAG
```bash
# Validate dependencies
gitlab-ci-local --dag
# Expected: Valid DAG, no circular deps
```

### Scenario 3: Simulate Branch
```bash
# Simulate main branch
gitlab-ci-local --branch main --dry-run
# Expected: Full pipeline with deployments
```

### Scenario 4: Test Changes
```bash
# Simulate changes to frontend
gitlab-ci-local --changes "services/frontend/**/*" --dry-run
# Expected: Only frontend jobs triggered
```

## 🎓 Learning Path

### Step 1: Overview (5 min)
Read this file and `PROJECT_SUMMARY.md`

### Step 2: Features (15 min)
Read `README.md` to understand all features

### Step 3: Deep Dive (30 min)
Read `FEATURES.md` to see proj1-19 mapping

### Step 4: Testing (45 min)
Follow `TESTING_GUIDE.md` to validate parser

## 🧪 Parser Test Checklist

Quick validation checklist:

- [ ] Parses without errors
- [ ] Generates 70+ jobs
- [ ] Identifies 12 stages
- [ ] Processes 4 includes
- [ ] Expands matrix (1 → 12 jobs)
- [ ] Resolves 7 YAML anchors
- [ ] Applies 10 extends templates
- [ ] Builds valid DAG
- [ ] Tracks all artifacts
- [ ] Parses all services
- [ ] Evaluates all rules
- [ ] Handles all reports

## 🏗️ Pipeline Flow

```
prebuild (validate, lint)
    ↓
build (compile services)
    ↓
test (unit, integration)
    ↓
security (SAST, dependency scan)
    ↓
quality (code quality)
    ↓
package (Docker images)
    ↓
deploy_dev (development)
    ↓
integration (E2E tests)
    ↓
deploy_stage (staging)
    ↓
performance (load tests)
    ↓
deploy_prod (MANUAL)
    ↓
cleanup
```

## 💡 Key Insights

### Why This Project Matters

1. **Comprehensive**: All features in one place
2. **Realistic**: Production monorepo patterns
3. **Complex**: Tests parser edge cases
4. **Educational**: Learn GitLab CI by example
5. **Practical**: Ready-to-use patterns

### What Makes It Challenging

1. **Scale**: 1068-line main config
2. **Depth**: Multi-level inheritance
3. **Breadth**: Every major feature
4. **Interactions**: Features combined in complex ways
5. **Services**: Real database orchestration

## 🎯 Use Cases

### For Parser Developers
- Validate comprehensive feature support
- Test edge cases and interactions
- Benchmark parsing performance
- Ensure correctness of DAG resolution

### For CI/CD Engineers
- Learn advanced GitLab CI patterns
- See monorepo pipeline structure
- Understand deployment workflows
- Study service orchestration

### For QA Teams
- Test pipeline simulation tools
- Validate YAML processing
- Check rule evaluation
- Verify artifact tracking

## 🔗 Next Steps

1. **Read**: Start with `README.md`
2. **Explore**: Browse `.gitlab-ci.yml`
3. **Test**: Follow `TESTING_GUIDE.md`
4. **Compare**: Check `FEATURES.md` for mapping

## 📚 Related Projects

- **proj1**: Simple script execution
- **proj2**: Basic stages
- **proj3**: Parallel jobs
- **proj4**: Artifacts
- **proj5**: Variables
- **proj6**: Artifact expiration
- **proj7**: Services
- **proj8**: Rules
- **proj9**: Cache
- **proj10**: Before/after scripts
- **proj11**: Includes
- **proj12**: YAML anchors
- **proj13**: Extends
- **proj14**: Retry/timeout
- **proj15**: Reports
- **proj16**: Child pipelines
- **proj17**: Matrix
- **proj18**: Resource groups

**proj20** = All of the above combined!

## ⚡ Quick Commands

```bash
# Navigate to project
cd test_ci_projects/proj20

# List all files
find . -type f

# View main config
less .gitlab-ci.yml

# Check line count
wc -l .gitlab-ci.yml

# View includes
ls .gitlab/ci/

# View services
ls services/
```

## ✅ Success Criteria

Your parser handles proj20 if it:

1. ✅ Parses without errors
2. ✅ Generates correct job count
3. ✅ Builds valid DAG
4. ✅ Resolves all templates
5. ✅ Evaluates rules correctly
6. ✅ Tracks dependencies
7. ✅ Handles services
8. ✅ Processes reports

## 🎉 Conclusion

**proj20 is the ultimate GitLab CI test project.**

It combines everything from proj1-proj19 into a realistic, production-grade monorepo pipeline that will thoroughly validate any GitLab CI parser implementation.

---

**Ready to test?** Start with `README.md` for the full documentation.

**Need specific info?** Check `INDEX.md` for a complete file listing.

**Want to test?** Follow `TESTING_GUIDE.md` step by step.
