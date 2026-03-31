# 🤝 Contributing to Osante Infrastructure

Thank you for your interest in contributing! This project is part of an academic portfolio.

## 📚 For Educational Use

Feel free to:
- Fork this repository for learning
- Review and test configurations
- Adapt for your own infrastructure
- Report issues or improvements

## 🐛 Reporting Issues

1. **Security Issues** — Use the `security` label
2. **Bugs** — Include steps to reproduce
3. **Feature Requests** — Explain your use case

## 🔧 Development Setup

```bash
# Fork and clone
git clone https://github.com/your-username/osante-dedik-settings.git
cd osante-dedik-settings

# Create branch
git checkout -b feature/your-feature

# Test in non-production environment
# ...

# Commit changes
git commit -m "feat: your changes"

# Push and create PR
git push origin feature/your-feature
```

## 📝 Commit Convention

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `security:` Security improvements
- `refactor:` Code refactoring

## ✅ Testing Requirements

Before submitting changes:

1. Test in non-production environment
2. Run validation script: `./scripts/validate-security.sh`
3. Update documentation if needed
4. Ensure backward compatibility

## 📖 Code Style

- Bash scripts: `set -Eeuo pipefail`
- Clear logging with timestamps
- Idempotent operations where possible
- Backup before modifications

## 🎓 Academic Use

This project is designed for educational purposes and demonstrates:
- Server hardening techniques
- Security best practices
- DevOps automation
- Infrastructure as Code principles

---

Thank you for contributing to secure infrastructure! 🔒
