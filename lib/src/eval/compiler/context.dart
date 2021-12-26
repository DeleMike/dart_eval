import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_eval/src/eval/compiler/source.dart';
import 'package:dart_eval/src/eval/compiler/type.dart';
import 'package:dart_eval/src/eval/compiler/variable.dart';
import 'package:dart_eval/src/eval/bridge/declaration.dart';
import 'package:dart_eval/src/eval/runtime/ops/all_ops.dart';
import 'package:dart_eval/src/eval/runtime/runtime.dart';

import 'offset_tracker.dart';

class CompilerContext {
  CompilerContext(this.sourceFile);

  final out = <DbcOp>[];
  int library = 0;
  int position = 0;
  int scopeFrameOffset = 0;
  ClassDeclaration? currentClass = null;
  List<List<AstNode>> scopeNodes = [];
  List<Map<String, Variable>> locals = [];
  Map<int, Map<String, DeclarationOrBridge>> topLevelDeclarationsMap = {};
  Map<int, Map<String, Map<String, Declaration>>> instanceDeclarationsMap = {};
  late OffsetTracker offsetTracker = OffsetTracker(this);
  Map<int, Map<String, TypeRef>> visibleTypes = {};
  Map<int, Map<String, DeclarationOrPrefix>> visibleDeclarations = {};
  Map<int, Map<String, int>> topLevelDeclarationPositions = {};
  Map<int, Map<String, List<Map<String, int>>>> instanceDeclarationPositions = {};
  List<int> allocNest = [0];
  List<bool> inNonlinearAccessContext = [false];

  bool get requireNonlinearAccess => inNonlinearAccessContext.last;

  int sourceFile;

  int pushOp(DbcOp op, int length) {
    out.add(op);
    position += length;
    return out.length - 1;
  }

  int rewriteOp(int where, DbcOp newOp, int lengthAdjust) {
    out[where] = newOp;
    position += lengthAdjust;
    return where;
  }

  void beginAllocScope({int existingAllocLen = 0, bool requireNonlinearAccess = false}) {
    allocNest.add(existingAllocLen);
    locals.add({});
    inNonlinearAccessContext.add(requireNonlinearAccess);
  }

  int peekAllocPops({int popAdjust = 0}) {
    return allocNest.last;
  }

  int endAllocScope({bool popValues = true, int popAdjust = 0}) {
    inNonlinearAccessContext.removeLast();
    locals.removeLast();
    final nestCount = allocNest.removeLast();
    if (popValues) {
      popN(nestCount + popAdjust);
      scopeFrameOffset -= nestCount;
    }
    return nestCount;
  }

  void popN(int pops) {
    if (pops == 0) {
      return;
    }
    pushOp(Pop.make(pops), Pop.LEN);
  }

  void resetStack({int position = 0}) {
    allocNest = [position];
    scopeFrameOffset = position;
    inNonlinearAccessContext = [false];
  }

  Variable setLocal(String name, Variable v) {
    return locals.last[name] = v
      ..name = name
      ..frameIndex = locals.length - 1;
  }

  Variable? lookupLocal(String name) {
    for (var i = locals.length - 1; i >= 0; i--) {
      if (locals[i].containsKey(name)) {
        return locals[i][name]!
          ..name = name
          ..frameIndex = i;
      }
    }
  }

  void resolveNonlinearity([int depth = 1]) {
    for (var i = 0; i < depth; i++) {
      <String, Variable>{...(locals[locals.length - depth])}.forEach((key, value) {
        locals[locals.length - depth][key] = value.unboxIfNeeded(this);
      });
    }
  }

  ContextSaveState saveStateForBranch() {
    final _state = ContextSaveState.of(this);
    return _state;
  }

  ContextSaveState restoreStateForBranch(ContextSaveState previous) {
    final _current = ContextSaveState.of(this);
    locals = previous.locals;
    allocNest = previous.allocNest;
    inNonlinearAccessContext = previous.inNonlinearAccessContext;
    return _current;
  }

  void resolveBranchStateDiscontinuity(ContextSaveState initial) {
    final _otherLocals = initial.locals;
    final _myLocals = [...locals];
    for (var i = 0; i < _otherLocals.length; i++) {
      final _otherLocalsMap = _otherLocals[i];
      final _myLocalsMap = _myLocals[i];

      _otherLocalsMap.forEach((key, value) {
        final myLocal = _myLocalsMap[key]!;
        if (!myLocal.boxed && value.boxed) {
          locals[i][key] = myLocal.boxIfNeeded(this);
        } else if (myLocal.boxed && !value.boxed) {
          locals[i][key] = myLocal.unboxIfNeeded(this);
        }
      });
    }
  }
}

class ContextSaveState {
  ContextSaveState.of(CompilerContext context)
      : locals = [...context.locals.map((e) => {...e})],
        allocNest = [...context.allocNest],
        inNonlinearAccessContext = [...context.inNonlinearAccessContext];
  List<Map<String, Variable>> locals;
  List<int> allocNest;
  List<bool> inNonlinearAccessContext;
}
