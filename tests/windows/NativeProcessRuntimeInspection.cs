using System;
using System.Reflection;
using System.Reflection.Emit;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Globalization;
using System.Collections.Generic;
using System.Security.Cryptography;

namespace PortableVBox
{
    // Test-only: reading metadata never invokes the inspected method.
    internal static class NativeProcessRuntimeInspection
    {
        internal static int TestManaged()
        {
            MethodInfo sample = typeof(NativeProcessRuntimeInspection).GetMethod("Sample", BindingFlags.NonPublic | BindingFlags.Static);
            string actual = Inspect(sample);
            Require(actual.Contains("\"status\":\"complete\""), "known managed method must decode");
            Require(actual.Contains("\"relative\"") && actual.Contains("\"target\""), "branches must include relative and absolute targets");
            Require(actual.Contains("switch"), "switch must decode");
            Require(actual.Contains("System.Math") && actual.Contains("Abs"), "method tokens must resolve");
            Require(Inspect(null).Contains("unsupported"), "missing target must be unsupported");
            MethodInfo noBody = typeof(IDisposable).GetMethod("Dispose");
            Require(Inspect(noBody).Contains("unsupported"), "bodyless target must be unsupported");
            Require(DecodeInvalid().Contains("unsupported"), "invalid IL must be unsupported");
            bool truncated = false; string decoded, calls;
            Decode(new byte[IlLimit + 1], sample.Module, sample, ref truncated, out decoded, out calls);
            Require(truncated, "large IL must explicitly mark truncation");
            byte[] lateCall = new byte[6006];
            lateCall[6000] = 0x28; // call after enough nops to exhaust verbose output
            MethodInfo abs = typeof(Math).GetMethod("Abs", new Type[] { typeof(int) });
            byte[] absToken = BitConverter.GetBytes(abs.MetadataToken);
            Array.Copy(absToken, 0, lateCall, 6001, 4);
            lateCall[6005] = 0x2a;
            truncated = false;
            string sparse, parts;
            Decode(lateCall, abs.Module, null, ref truncated, out decoded, out calls, out sparse, out parts);
            Require(truncated && calls.Contains("Abs") && calls.Contains("6000"), "late call must survive verbose instruction truncation");
            Require(sparse.Contains("Abs") && sparse.Contains("6000"), "late resolved token must survive verbose truncation");
            Require(parts.Contains("\"verbose_instructions_truncated\":true") && parts.Contains("\"il_scan_truncated\":false")
                && parts.Contains("\"call_records_truncated\":false") && parts.Contains("\"sparse_records_truncated\":false"), "truncation must be explicit per part");
            truncated = false;
            Decode(new byte[] { 0x28, 0xff, 0xff, 0xff, 0xff, 0x2a }, sample.Module, sample, ref truncated, out decoded, out calls, out sparse, out parts);
            Require(parts.Contains("\"unresolved_token_count\":1") && parts.Contains("\"token_mapping_status\":\"unsupported\""), "unresolved token mapping cannot be complete");
            string capture = Capture();
            Require(Encoding.UTF8.GetByteCount(capture) <= JsonLimit, "capture must respect byte bound");
            Require(capture.Contains("\"mutation_authorized\":false"), "capture cannot grant mutation authority");
            Require(capture.Contains("clr_version") && capture.Contains("inspection_status"), "capture must identify runtime and status");
            Require(capture.Contains("on-disk Process assembly path hash; loaded module MVID separately; association not attested"), "file hash must not attest loaded bytes");
            string unavailableMetadata = CaptureForPaths("", null);
            string unavailableHash = CaptureForPaths(null, "");
            Require(!unavailableMetadata.Contains(":,") && !unavailableHash.Contains(":,"), "unavailable metadata/hash must not leave dangling JSON values");
            Require(unavailableMetadata.Contains("\"assembly_file_status\":\"unsupported\"") && unavailableHash.Contains("\"assembly_file_status\":\"unsupported\""), "unavailable metadata/hash must report unsupported");
            return 0;
        }

        private static int Sample(int value)
        {
            if (value < 0) return Math.Abs(value);
            switch (value) { case 0: return 11; case 1: return 23; case 2: return 37; case 3: return 43; case 4: return 59; default: return 61; }
        }

        private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
        private const int IlLimit = 8192;
        private const int JsonLimit = 128 * 1024;
        private static readonly Dictionary<short, OpCode> Codes = BuildCodes();

        private static Dictionary<short, OpCode> BuildCodes()
        {
            Dictionary<short, OpCode> codes = new Dictionary<short, OpCode>();
            foreach (FieldInfo field in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
                if (field.FieldType == typeof(OpCode)) { OpCode code = (OpCode)field.GetValue(null); codes[code.Value] = code; }
            return codes;
        }

        // ASCII-only JSON means the character limit also bounds UTF-8 bytes.
        private static string Q(string value)
        {
            if (value == null) return "null";
            StringBuilder b = new StringBuilder("\"");
            foreach (char c in value)
            {
                if (c == '"' || c == '\\') b.Append('\\').Append(c);
                else if (c < 32 || c > 126) b.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                else b.Append(c);
            }
            return b.Append('"').ToString();
        }
        private static string Label(string value, ref bool truncated)
        {
            if (value != null && value.Length > 512) { truncated = true; return value.Substring(0, 512); }
            return value;
        }
        private static string N(int value) { return value.ToString(CultureInfo.InvariantCulture); }
        private static string Hex(byte[] bytes, int count)
        {
            StringBuilder b = new StringBuilder(count * 2);
            for (int i = 0; i < count; i++) b.Append(bytes[i].ToString("x2", CultureInfo.InvariantCulture));
            return b.ToString();
        }
        private static string Unsupported(string reason) { return "{\"status\":\"unsupported\",\"reason\":" + Q(reason) + "}"; }
        private static string Inspect(MethodInfo method)
        {
            if (method == null) return Unsupported("StartWithCreateProcess target missing or ambiguous");
            try
            {
                MethodBody body = method.GetMethodBody();
                if (body == null) return Unsupported("target has no inspectable managed body");
                byte[] il = body.GetILAsByteArray();
                if (il == null) return Unsupported("target IL is unavailable");
                bool truncated = il.Length > IlLimit;
                string instructions, calls, sparse, partStatus;
                Decode(il, method.Module, method, ref truncated, out instructions, out calls, out sparse, out partStatus);
                StringBuilder locals = new StringBuilder("[");
                int count = 0;
                foreach (LocalVariableInfo local in body.LocalVariables)
                {
                    if (count == 16) { truncated = true; break; }
                    if (count++ != 0) locals.Append(',');
                    locals.Append("{\"index\":").Append(N(local.LocalIndex)).Append(",\"type\":").Append(Q(Label(local.LocalType.ToString(), ref truncated)))
                        .Append(",\"pinned\":").Append(local.IsPinned ? "true" : "false").Append('}');
                }
                locals.Append(']');
                StringBuilder regions = new StringBuilder("["); count = 0;
                foreach (ExceptionHandlingClause clause in body.ExceptionHandlingClauses)
                {
                    if (count == 16) { truncated = true; break; }
                    if (count++ != 0) regions.Append(',');
                    regions.Append("{\"flags\":").Append(Q(clause.Flags.ToString())).Append(",\"try_offset\":").Append(N(clause.TryOffset))
                        .Append(",\"try_length\":").Append(N(clause.TryLength)).Append(",\"handler_offset\":").Append(N(clause.HandlerOffset))
                        .Append(",\"handler_length\":").Append(N(clause.HandlerLength));
                    if (clause.Flags == ExceptionHandlingClauseOptions.Filter) regions.Append(",\"filter_offset\":").Append(N(clause.FilterOffset));
                    if (clause.Flags == ExceptionHandlingClauseOptions.Clause) regions.Append(",\"catch_type\":").Append(Q(Label(clause.CatchType == null ? null : clause.CatchType.ToString(), ref truncated)));
                    regions.Append('}');
                }
                regions.Append(']');
                string identity = Label(method.ToString(), ref truncated);
                return "{\"status\":" + Q(partStatus.Contains("\"token_mapping_status\":\"unsupported\"") ? "unsupported" : truncated ? "bounded-truncated" : "complete") + ",\"method\":" + Q(identity)
                    + ",\"metadata_token\":" + N(method.MetadataToken) + ",\"max_stack\":" + N(body.MaxStackSize)
                    + ",\"init_locals\":" + (body.InitLocals ? "true" : "false") + ",\"il_total_bytes\":" + N(il.Length)
                    + ",\"il_captured_bytes\":" + N(Math.Min(il.Length, IlLimit)) + ",\"raw_il_hex\":" + Q(Hex(il, Math.Min(il.Length, IlLimit)))
                    + ",\"locals_truncated\":" + (body.LocalVariables.Count > 16 ? "true" : "false")
                    + ",\"exception_regions_truncated\":" + (body.ExceptionHandlingClauses.Count > 16 ? "true" : "false")
                    + ",\"raw_il_truncated\":" + (il.Length > IlLimit ? "true" : "false")
                    + ",\"locals\":" + locals + ",\"exception_regions\":" + regions + ",\"instructions\":" + instructions + ",\"calls_in_il_offset_order\":" + calls
                    + ",\"sparse_token_and_branch_records\":" + sparse + ",\"decode_parts\":" + partStatus + "}";
            }
            catch (Exception ex) { return Unsupported("metadata or IL inspection failed: " + ex.GetType().Name); }
        }

        private static void Need(byte[] il, int position, int count)
        {
            if (count < 0 || position < 0 || position > il.Length - count) throw new InvalidDataException("incomplete IL operand");
        }
        private static int I4(byte[] il, ref int position)
        {
            Need(il, position, 4);
            int result = il[position] | (il[position + 1] << 8) | (il[position + 2] << 16) | (il[position + 3] << 24);
            position += 4; return result;
        }
        private static string Resolve(Module module, MethodInfo method, int token, OperandType kind, ref bool truncated)
        {
            try
            {
                Type[] types = method != null && method.DeclaringType != null ? method.DeclaringType.GetGenericArguments() : null;
                Type[] args = method == null ? null : method.GetGenericArguments();
                if (kind == OperandType.InlineString) return Q("string token (content intentionally omitted)");
                if (kind == OperandType.InlineSig)
                {
                    byte[] signature = module.ResolveSignature(token);
                    if (signature.Length > 128) truncated = true;
                    return Q("signature:" + Hex(signature, Math.Min(signature.Length, 128)));
                }
                MemberInfo member = module.ResolveMember(token, types, args);
                return Q(Label((member.DeclaringType == null ? "" : member.DeclaringType.FullName + "::") + member.ToString(), ref truncated));
            }
            catch (Exception ex) { return Q("unresolved:" + ex.GetType().Name); }
        }
        private static void Decode(byte[] il, Module module, MethodInfo method, ref bool truncated, out string instructions, out string calls)
        {
            string sparse, parts;
            Decode(il, module, method, ref truncated, out instructions, out calls, out sparse, out parts);
        }
        private static void Decode(byte[] il, Module module, MethodInfo method, ref bool truncated, out string instructions, out string calls, out string sparse, out string parts)
        {
            StringBuilder list = new StringBuilder("["), callList = new StringBuilder("[");
            StringBuilder sparseList = new StringBuilder("[");
            bool verboseTruncated = false, callsTruncated = false, sparseTruncated = false, scanTruncated = false;
            int sparseCount = 0, unresolvedTokens = 0;
            int position = 0, count = 0, callCount = 0;
            while (position < il.Length)
            {
                if (position >= IlLimit) { truncated = scanTruncated = true; break; }
                int offset = position;
                short code = il[position++];
                if (code == 0xfe) { Need(il, position, 1); code = (short)(0xfe00 | il[position++]); }
                OpCode op;
                if (!Codes.TryGetValue(code, out op)) throw new InvalidDataException("unknown opcode");
                string operand = "null", resolved = null;
                int token;
                switch (op.OperandType)
                {
                    case OperandType.InlineNone: break;
                    case OperandType.ShortInlineBrTarget:
                        Need(il, position, 1); int smallDelta = (sbyte)il[position++];
                        operand = "{\"relative\":" + N(smallDelta) + ",\"target\":" + N(checked(position + smallDelta)) + "}"; break;
                    case OperandType.InlineBrTarget:
                        int delta = I4(il, ref position); operand = "{\"relative\":" + N(delta) + ",\"target\":" + N(checked(position + delta)) + "}"; break;
                    case OperandType.InlineSwitch:
                        int size = I4(il, ref position);
                        if (size < 0) throw new InvalidDataException("negative switch size");
                        if (size > 256) { truncated = scanTruncated = true; goto Finish; }
                        Need(il, position, checked(size * 4)); int end = position + size * 4; StringBuilder targets = new StringBuilder("[");
                        for (int i = 0; i < size; i++) { int d = I4(il, ref position); if (i != 0) targets.Append(','); targets.Append("{\"relative\":").Append(N(d)).Append(",\"target\":").Append(N(checked(end + d))).Append('}'); }
                        operand = targets.Append(']').ToString(); break;
                    case OperandType.ShortInlineI: Need(il, position, 1); operand = N((sbyte)il[position++]); break;
                    case OperandType.ShortInlineVar: Need(il, position, 1); operand = N(il[position++]); break;
                    case OperandType.InlineVar: Need(il, position, 2); operand = N(il[position] | il[position + 1] << 8); position += 2; break;
                    case OperandType.InlineI: operand = N(I4(il, ref position)); break;
                    case OperandType.InlineI8: case OperandType.InlineR: case OperandType.ShortInlineR:
                        int width = op.OperandType == OperandType.ShortInlineR ? 4 : 8; Need(il, position, width);
                        byte[] raw = new byte[width]; Array.Copy(il, position, raw, 0, width); position += width;
                        operand = "{\"little_endian_hex\":" + Q(Hex(raw, width)) + "}"; break;
                    case OperandType.InlineField: case OperandType.InlineMethod: case OperandType.InlineType: case OperandType.InlineTok: case OperandType.InlineString: case OperandType.InlineSig:
                        token = I4(il, ref position); resolved = Resolve(module, method, token, op.OperandType, ref truncated);
                        if (resolved.StartsWith("\"unresolved:", StringComparison.Ordinal)) unresolvedTokens++;
                        operand = "{\"token\":" + N(token) + ",\"resolved\":" + resolved + "}"; break;
                    default: throw new InvalidDataException("unsupported operand encoding");
                }
                if (position > IlLimit) { truncated = scanTruncated = true; break; }
                string record = "{\"offset\":" + N(offset) + ",\"next_offset\":" + N(position) + ",\"opcode\":" + Q(op.Name)
                    + ",\"flow_control\":" + Q(op.FlowControl.ToString()) + ",\"operand\":" + operand + "}";
                if (list.Length + record.Length + 2 <= 24000)
                {
                    if (count++ != 0) list.Append(',');
                    list.Append(record);
                }
                else truncated = verboseTruncated = true;
                if (resolved != null || op.OperandType == OperandType.InlineBrTarget || op.OperandType == OperandType.ShortInlineBrTarget || op.OperandType == OperandType.InlineSwitch)
                {
                    if (sparseList.Length + record.Length + 2 <= 16000)
                    {
                        if (sparseCount++ != 0) sparseList.Append(',');
                        sparseList.Append(record);
                    }
                    else truncated = sparseTruncated = true;
                }
                if (op.FlowControl == FlowControl.Call || op == OpCodes.Jmp)
                {
                    callCount++;
                    string callRecord = "{\"order\":" + N(callCount) + ",\"offset\":" + N(offset) + ",\"opcode\":" + Q(op.Name) + ",\"reference\":" + (resolved ?? "null") + "}";
                    if (callList.Length + callRecord.Length + 2 <= 16000)
                    {
                        if (callList.Length > 1) callList.Append(',');
                        callList.Append(callRecord);
                    }
                    else truncated = callsTruncated = true;
                }
            }
            Finish:
            instructions = list.Append(']').ToString(); calls = callList.Append(']').ToString(); sparse = sparseList.Append(']').ToString();
            parts = "{\"il_scan_truncated\":" + (scanTruncated ? "true" : "false")
                + ",\"verbose_instructions_truncated\":" + (verboseTruncated ? "true" : "false")
                + ",\"call_records_truncated\":" + (callsTruncated ? "true" : "false")
                + ",\"sparse_records_truncated\":" + (sparseTruncated ? "true" : "false")
                + ",\"unresolved_token_count\":" + N(unresolvedTokens)
                + ",\"token_mapping_status\":" + Q(unresolvedTokens > 0 ? "unsupported" : scanTruncated ? "bounded-truncated" : "complete")
                + ",\"calls_seen_in_scanned_il\":" + N(callCount) + "}";
        }
        private static string DecodeInvalid()
        {
            try { bool truncated = false; string instructions, calls; Decode(new byte[] { 0xfe }, typeof(NativeProcessRuntimeInspection).Module, null, ref truncated, out instructions, out calls); return "{}"; }
            catch (InvalidDataException) { return Unsupported("invalid IL"); }
        }
        internal static string Capture()
        {
            return CaptureForPath(null);
        }
        // Test seam only: production-facing capture always uses the real assembly path.
        private static string CaptureForPath(string testPath)
        {
            return CaptureForPaths(testPath, null);
        }
        private static string CaptureForPaths(string testPath, string testHashPath)
        {
            const string caveat = "Ordered calls alone are not control-flow proof. Reference source from the 4.7.2 family does not attest the serviced .NET Framework 4.8 runtime. Inspection grants no launch, retry, or mutation authority.";
            bool truncated = false;
            StringBuilder data = new StringBuilder("{\"mutation_authorized\":false,\"caveat\":").Append(Q(caveat));
            string inspection;
            try
            {
                Assembly assembly = typeof(Process).Assembly;
                // Evaluate fallible metadata before touching the surrounding JSON object.
                string clr = Q(Environment.Version.ToString());
                string os = Q(Label(Environment.OSVersion.ToString(), ref truncated));
                string bitness = Environment.Is64BitProcess ? "true" : "false";
                string identity = Q(Label(assembly.FullName, ref truncated));
                string mvid = Q(typeof(Process).Module.ModuleVersionId.ToString());
                string location = testPath ?? assembly.Location;
                string locationJson = Q(Label(location, ref truncated));
                data.Append(",\"clr_version\":").Append(clr).Append(",\"os_version\":").Append(os)
                    .Append(",\"is_64_bit_process\":").Append(bitness)
                    .Append(",\"process_assembly_identity\":").Append(identity)
                    .Append(",\"process_assembly_mvid\":").Append(mvid)
                    .Append(",\"process_assembly_location\":").Append(locationJson)
                    .Append(",\"assembly_hash_scope\":").Append(Q("on-disk Process assembly path hash; loaded module MVID separately; association not attested"));
                try
                {
                    string fileVersion = Q(Label(FileVersionInfo.GetVersionInfo(location).FileVersion, ref truncated));
                    string diskHash;
                    // Deny write/delete sharing while hashing where the OS honors sharing modes.
                    // This still cannot establish that the loaded module has these disk bytes.
                    using (FileStream stream = new FileStream(testHashPath ?? location, FileMode.Open, FileAccess.Read, FileShare.Read))
                    using (SHA256 hash = SHA256.Create()) diskHash = Q(Hex(hash.ComputeHash(stream), 32));
                    data.Append(",\"process_assembly_file_version\":").Append(fileVersion)
                        .Append(",\"process_assembly_sha256\":").Append(diskHash);
                    data.Append(",\"assembly_file_status\":\"complete\"");
                }
                catch (Exception ex) { data.Append(",\"assembly_file_status\":\"unsupported\",\"assembly_file_error\":").Append(Q(ex.GetType().Name)); }
                MethodInfo target = null; int matches = 0;
                foreach (MethodInfo method in typeof(Process).GetMethods(BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
                    if (method.Name == "StartWithCreateProcess") { target = method; matches++; }
                inspection = Inspect(matches == 1 ? target : null);
            }
            catch (Exception ex) { inspection = Unsupported("runtime metadata unavailable: " + ex.GetType().Name); }
            string status = inspection.Contains("\"status\":\"unsupported\"") || data.ToString().Contains("\"assembly_file_status\":\"unsupported\"") ? "unsupported" : truncated || inspection.Contains("bounded-truncated") ? "bounded-truncated" : "complete";
            data.Append(",\"inspection_status\":").Append(Q(status)).Append(",\"method_inspection\":").Append(inspection).Append('}');
            if (data.Length > JsonLimit) return "{\"mutation_authorized\":false,\"inspection_status\":\"bounded-truncated\",\"reason\":\"JSON size limit reached\",\"caveat\":" + Q(caveat) + "}";
            return data.ToString();
        }
    }
}
