#!/usr/bin/env python3
"""Reproduce the report with mCRL2; generated files stay outside the repository.

Usage: python3 verify.py [--tools-dir /path/to/mcrl2/bin] [--output-dir /tmp/results]
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tools-dir', type=Path)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    tools = args.tools_dir
    if tools is None:
        executable = shutil.which('mcrl22lps')
        tools = Path(executable).parent if executable else Path('/Applications/mCRL2.app/Contents/bin')
    out = args.output_dir or Path(tempfile.mkdtemp(prefix='crossing-verification-'))
    out.mkdir(parents=True, exist_ok=True)
    commands = []

    def run(tool, *arguments):
        command = [str(tools / tool), *map(str, arguments)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
        commands.append({'command': command, 'exit_code': result.returncode, 'output': output})
        require(result.returncode == 0, f'{tool} failed:\n{output}')
        require(not re.search(r'\b(warning|error)\b', output, re.I), f'{tool} diagnostic:\n{output}')
        return output.strip()

    version = run('mcrl22lps', '--version').splitlines()[0]
    properties = {}
    for task in ('1', '2'):
        project = ET.parse(ROOT / task / f'{task}.mcrl2proj').getroot()
        names = [node.text for node in project.findall('./properties/property')]
        require(set(names) == {p.stem for p in (ROOT / task / 'properties').glob('*.mcf')},
                f'Task {task}: project and property files disagree')
        require(project.findtext('spec') == f'{task}_spec.mcrl2', f'Task {task}: unexpected specification')
        properties[task] = {name: ROOT / task / 'properties' / f'{name}.mcf' for name in names}

    # Check 5a and 5b separately, using the conjuncts from the saved formula.
    source = properties['2']['Liveness per train'].read_text()
    source = '\n'.join(line.split('%', 1)[0] for line in source.splitlines()).strip()
    match = re.fullmatch(r'(forall\s+[^.]+\.\s*)(.*)', source, re.S)
    require(match is not None, 'Cannot extract the liveness quantifier')
    parts = match[2].split('&&')
    require(len(parts) == 2, 'Expected exactly two liveness conjuncts')
    for name, body in zip(('5a', '5b'), parts):
        formula = out / f'{name}.mcf'
        formula.write_text(match[1] + body.strip() + '\n')
        properties['2'][name] = formula

    base1 = (ROOT / '1/1_spec.mcrl2').read_text()
    base2 = (ROOT / '2/2_spec.mcrl2').read_text()
    variants = [
        ('1/variants/grant_before_down.mcrl2', base1,
         '. lower_controller . down_controller\n    . grant_controller',
         '. lower_controller . grant_controller\n    . down_controller'),
        ('2/variants/naive_raise.mcrl2', base2,
         'CONTROLLER(tail(queue), free, gate)', 'CONTROLLER(tail(queue), free, opening)'),
        ('2/variants/missed_increment.mcrl2', base2,
         'CONTROLLER(queue <| t, crossing, gate)',
         'CONTROLLER(if(crossing == busy, queue, queue <| t), crossing, gate)'),
        ('2/variants/off_by_one.mcrl2', base2,
         'CONTROLLER(tail(queue), free, gate)', 'CONTROLLER(tail(queue), busy, gate)'),
    ]
    for relative, base, old, new in variants:
        require(base.count(old) == 1, f'{relative}: mutation site changed')
        require((ROOT / relative).read_text() == base.replace(old, new),
                f'{relative}: does not match the reported mutation')

    scenarios = [
        ('task1', '1', '1/1_spec.mcrl2', set()),
        ('grant_before_down', '1', '1/variants/grant_before_down.mcrl2', {'Safety'}),
        ('task2', '2', '2/2_spec.mcrl2', {'Road avaliability infinite opening'}),
        ('naive_raise', '2', '2/variants/naive_raise.mcrl2',
         {'Deadlock freedom', 'Liveness per train', '5a', 'Road Avaliability',
          'Road avaliability infinite opening', 'Non vacuity'}),
        ('missed_increment', '2', '2/variants/missed_increment.mcrl2',
         {'No premature raising', 'Liveness per train', '5a', '5b',
          'Road avaliability infinite opening', 'Non vacuity'}),
        ('off_by_one', '2', '2/variants/off_by_one.mcrl2',
         {'Deadlock freedom', 'Liveness per train', '5a', 'Road Avaliability',
          'Road avaliability infinite opening', 'Non vacuity'}),
    ]
    results, graphs = {}, {}
    for name, task, relative, expected_false in scenarios:
        lps = out / f'{name}.lps'
        run('mcrl22lps', ROOT / relative, lps)
        rows = {}
        for index, (prop, formula) in enumerate(properties[task].items()):
            pbes = out / f'{name}-{index}.pbes'
            run('lps2pbes', '-f', formula, lps, pbes)
            answer = run('pbes2bool', pbes)
            expected = 'false' if prop in expected_false else 'true'
            require(answer == expected, f'{name}: {prop}: expected {expected}, got {answer}')
            rows[prop] = answer
        results[name] = rows
        aut = out / f'{name}.aut'
        run('lps2lts', lps, aut)
        lines = aut.read_text().splitlines()
        initial = int(re.match(r'des \((\d+),', lines[0])[1])
        edges = {}
        for line in lines[1:]:
            match = re.fullmatch(r'\((\d+),"(.*)",(\d+)\)', line)
            require(match is not None, f'Unexpected AUT line: {line}')
            edges.setdefault(int(match[1]), []).append((match[2], int(match[3])))
        graphs[name] = (initial, edges)
        print(f'{name}: all {len(rows)} expected results confirmed', flush=True)

    def follow(graph, states, trace):
        _, edges = graph

        def closure(current):
            seen, todo = set(current), list(current)
            while todo:
                for action, target in edges.get(todo.pop(), []):
                    if action == 'tau' and target not in seen:
                        seen.add(target)
                        todo.append(target)
            return seen

        states = closure(states)
        for action in trace:
            states = closure({v for u in states for label, v in edges.get(u, []) if label == action})
        return states

    cycle = ['approach(t1)', 'grant(t1)', 'enter(t1)', 'exit(t1)', 'leave(t1)']
    traces = {
        'grant_before_down': ['approach', 'enter'],
        'naive_raise': ['approach(t1)', 'grant(t1)', 'enter(t1)', 'approach(t2)', 'exit(t1)', 'leave(t1)'],
        'missed_increment': ['approach(t1)', 'grant(t1)', 'enter(t1)', 'approach(t2)'],
        'off_by_one': cycle,
    }
    for name, trace in traces.items():
        require(follow(graphs[name], {graphs[name][0]}, trace), f'{name}: reported trace does not exist')
    reachable = follow(graphs['task2'], {graphs['task2'][0]}, cycle)
    require(any(state in follow(graphs['task2'], {state}, cycle) for state in reachable),
            'The reported infinite closed-gate cycle does not exist')
    print('All reported trace prefixes and the closed-gate cycle confirmed', flush=True)

    # Independently check the prose claim of inevitable entry, beyond 5a/5b.
    must_enter = out / 'inevitable-entry.mcf'
    must_enter.write_text('forall t: Id . [true*.approach(t)] mu X . (<true>true && [!enter(t)]X)\n')
    pbes = out / 'inevitable-entry.pbes'
    run('lps2pbes', '-f', must_enter, out / 'task2.lps', pbes)
    require(run('pbes2bool', pbes) == 'true', 'The FIFO eventual-entry argument does not hold')

    def counts(lps, name, expected):
        full, reduced = out / f'{name}.lts', out / f'{name}-reduced.lts'
        run('lps2lts', lps, full)
        run('ltsconvert', '-e', 'branching-bisim', full, reduced)
        actual = [int(re.search(r'Number of states: (\d+)', run('ltsinfo', path))[1])
                  for path in (full, reduced)]
        require(actual == list(expected), f'{name}: expected {expected} states, got {actual}')
        return actual

    state_counts = {'task1': counts(out / 'task1.lps', 'task1', (9, 5))}
    for n, expected in enumerate(((10, 8), (31, 23), (108, 78), (451, 323), (2278, 1628), (13695, 9783)), 1):
        spec = base2.replace('Id = struct t1 | t2 | t3;',
                             'Id = struct ' + ' | '.join(f't{i}' for i in range(1, n + 1)) + ';')
        spec = spec.replace('TRAIN(t1) || TRAIN(t2) || TRAIN(t3)',
                            ' || '.join(f'TRAIN(t{i})' for i in range(1, n + 1)))
        specification, lps = out / f'n{n}.mcrl2', out / f'n{n}.lps'
        specification.write_text(spec)
        run('mcrl22lps', specification, lps)
        state_counts[str(n)] = counts(lps, f'n{n}', expected)
    print('All full/reduced state counts confirmed for N=1..6', flush=True)

    inputs = [p for task in ('1', '2') for p in sorted((ROOT / task).rglob('*')) if p.is_file()]
    summary = {'tool_version': version, 'properties': results, 'state_counts': state_counts,
               'trace_checks': 'passed', 'inevitable_entry': 'true',
               'input_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
               'commands': commands}
    (out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f'Verification passed. Evidence: {out / "results.json"}')


if __name__ == '__main__':
    main()
