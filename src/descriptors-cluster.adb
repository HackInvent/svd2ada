------------------------------------------------------------------------------
--                                                                          --
--                          SVD Binding Generator                           --
--                                                                          --
--                    Copyright (C) 2015-2016, AdaCore                      --
--                                                                          --
-- SVD2Ada is free software;  you can  redistribute it  and/or modify it    --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software  Foundation;  either version 3,  or (at your option) any later  --
-- version.  SVD2Ada is distributed in the hope that it will be useful, but --
-- WITHOUT ANY WARRANTY;  without even the  implied warranty of MERCHANTA-  --
-- BILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public  --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General Public License  distributed with SVD2Ada; see file COPYING3.  If --
-- not, go to http://www.gnu.org/licenses for a complete copy of the        --
-- license.                                                                 --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Containers.Indefinite_Vectors;

with DOM.Core;
with DOM.Core.Elements;  use DOM.Core.Elements;
with DOM.Core.Nodes;

package body Descriptors.Cluster is

   procedure Insert_Element
     (Cluster : in out Cluster_T;
      Elt     : Peripheral_Element);

   procedure Dump_Cluster_Type
     (Spec      : in out Ada_Gen.Ada_Spec;
      Cluster   : in out Cluster_T;
      Type_Name : String);

   package String_List is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

--
--     function Find_Overlapping_Registers
--       (Reg_Set : Register_Vectors.Vector) return Boolean;
--
--     function Less (P1, P2 : Cluster_T) return Boolean;
--
--     package Cluster_Sort is new Cluster_Vectors.Generic_Sorting
--       (Less);
--
--     package String_List is new Ada.Containers.Indefinite_Vectors
--       (Positive, String);
--
--     ----------
--     -- Less --
--     ----------
--
--     function Less (P1, P2 : Cluster_T) return Boolean
--     is
--     begin
--        return P1.Base_Address < P2.Base_Address;
--     end Less;

   ---------------------
   -- Read_Cluster --
   ---------------------

   function Read_Cluster
     (Elt            : DOM.Core.Element;
      Prepend        : Unbounded.Unbounded_String;
      Append         : Unbounded.Unbounded_String;
      Reg_Properties : Register_Properties_T;
      Db             : Cluster_Db'Class) return Cluster_T
   is
      use DOM.Core;
      use type Ada.Strings.Unbounded.Unbounded_String;

      List         : constant Node_List := Nodes.Child_Nodes (Elt);
      Ret          : Cluster_T;
      Derived_From : constant String :=
                       Elements.Get_Attribute (Elt, "derivedFrom");
      Register     : Register_Access;
      Reg2         : Register_Access;
      Cluster      : Cluster_Access;

      ------------------
      -- Compute_Name --
      ------------------

      function Compute_Name return Unbounded.Unbounded_String
      is
      begin
         if Ret.Dim = 1 then
            return Ret.Xml_Id;
         else
            declare
               Name : constant String := Unbounded.To_String (Ret.Xml_Id);
               Ret  : String (Name'Range);
               Idx  : Natural;
               Skip : Boolean := False;
            begin
               Idx := Ret'First - 1;

               for J in Name'Range loop
                  if Skip then
                     Skip := False;

                  elsif Name (J) = '['
                    or else Name (J) = ']'
                  then
                     null;

                  elsif J < Name'Last and then Name (J .. J + 1) = "%s" then
                     --  Skip the next character (e.g. 's')
                     Skip := True;

                  else
                     Idx := Idx + 1;
                     Ret (Idx) := Name (J);
                  end if;
               end loop;

               if Idx in Ret'Range and then Ret (Idx) = '_' then
                  Idx := Idx - 1;
               end if;

               return Unbounded.To_Unbounded_String (Ret (Ret'First .. Idx));
            end;
         end if;
      end Compute_Name;

   begin
      Ret.Reg_Properties := Reg_Properties;

      if Derived_From /= "" then
         declare
            Oth : Cluster_Access renames Db.Get_Cluster (Derived_From);
         begin
            if Oth /= null then
               Ret := Oth.all;
               Ret.Content.Clear;

               for Elt of Oth.Content loop
                  Ret.Content.Append (Deep_Copy (Elt));
               end loop;

            else
               raise Constraint_Error with
                 "cluster 'derivedFrom' is not known: " & Derived_From;
            end if;
         end;
      end if;

      for J in 0 .. Nodes.Length (List) - 1 loop
         if Nodes.Node_Type (Nodes.Item (List, J)) = Element_Node then
            declare
               Child : constant Element := Element (Nodes.Item (List, J));
               Tag   : String renames Elements.Get_Tag_Name (Child);
            begin
               if Tag = "name" then
                  Ret.Xml_Id := Get_Value (Child);
                  Ret.Name := Compute_Name;
                  Ret.Type_Name := Prepend & Ret.Name & Append;

               elsif Tag = "headerStructName" then
                  Ret.Type_Name := Get_Value (Child);

               elsif Tag = "description" then
                  Ret.Description := Get_Value (Child);

               elsif Tag = "alternateCluster" then
                  null;

               elsif Tag = "addressOffset" then
                  Ret.Address_Offset := Get_Value (Child);

               elsif Tag = "dim" then
                  Ret.Dim := Get_Value (Child);

                  if Unbounded.Length (Ret.Xml_Id) > 0 then
                     Ret.Name := Compute_Name;
                  end if;

               elsif Tag = "dimIncrement" then
                  Ret.Dim_Increment := Get_Value (Child);

               elsif Tag = "dimIndex" then
                  Ret.Dim_Index := Get_Value (Child);

               elsif Tag = "register" then
                  Register := Read_Register
                    (Child,
                     Prepend,
                     Append & Unbounded.To_String (Ret.Name) & "_",
                     Ret.Reg_Properties,
                     Ret);

                  if Register.Dim > 1
                    and then Register.Dim_Increment /=
                      Register.Reg_Properties.Size / 8
                  then
                     --  in such case, this certainly indicates
                     --  two intertwined arrays of registers, We
                     --  need in this case to expand the erray
                     --  into individual values
                     for J in 0 .. Register.Dim - 1 loop
                        Reg2 := new Register_T'(Register.all);
                        Reg2.Dim := 1;
                        Reg2.Address_Offset :=
                          Register.Address_Offset +
                            J * Register.Dim_Increment;
                        Reg2.Name :=
                          Register.Name & To_String (J);
                        Insert_Element (Ret, +Reg2);
                     end loop;
                  else
                     Insert_Element (Ret, +Register);
                  end if;

               elsif Tag = "cluster" then
                  Cluster := new Cluster_T'
                    (Read_Cluster
                       (Child,
                        Prepend,
                        Append,
                        Ret.Reg_Properties,
                        Ret));
                  Insert_Element (Ret, +Cluster);

               else
                  Ada.Text_IO.Put_Line
                    ("*** WARNING: ignoring peripheral element " & Tag);
               end if;
            end;
         end if;
      end loop;

      return Ret;
   end Read_Cluster;

   ---------------
   -- Deep_Copy --
   ---------------

   function Deep_Copy (Cluster : Cluster_Access) return Cluster_Access
   is
      Ret : constant Cluster_Access := new Cluster_T'(Cluster.all);
   begin
      Ret.Content.Clear;

      for Elt of Cluster.Content loop
         case Elt.Kind is
            when Register_Element =>
               Ret.Content.Append
                 ((Register_Element, new Register_T'(Elt.Reg.all)));
            when Cluster_Element =>
               Ret.Content.Append
                 ((Cluster_Element, Deep_Copy (Elt.Cluster)));
         end case;
      end loop;

      return Ret;
   end Deep_Copy;

   ------------------
   -- Get_Register --
   ------------------

   overriding function Get_Register
     (Db     : Cluster_T;
      XML_Id : String) return Register_Access
   is
   begin
      for Elt of Db.Content loop
         if Elt.Kind = Register_Element
           and then Ada.Strings.Unbounded.To_String (Elt.Reg.XML_Id) = XML_Id
         then
            return Elt.Reg;
         end if;
      end loop;

      return null;
   end Get_Register;

   -----------------
   -- Get_Cluster --
   -----------------

   overriding function Get_Cluster
     (Db     : Cluster_T;
      XML_Id : String) return Cluster_Access
   is
   begin
      for Elt of Db.Content loop
         if Elt.Kind = Cluster_Element
           and then Unbounded.To_String (Elt.Cluster.Xml_Id) = XML_Id
         then
            return Elt.Cluster;
         end if;
      end loop;

      return null;
   end Get_Cluster;

   -------------
   -- Get_MSB --
   -------------

   function Get_Size (Cluster : Cluster_T) return Positive
   is
      Elt : Peripheral_Element renames Cluster.Content.Last_Element;
      Ret : Natural := 0;

   begin
      if Cluster.Dim > 1 then
         return Cluster.Dim_Increment * 8;
      end if;

      Ret := 8 * Address_Offset (Elt);

      case Elt.Kind is
         when Register_Element =>
            Ret := Ret +
              (if Elt.Reg.Dim = 1
               then Elt.Reg.Reg_Properties.Size
               else Elt.Reg.Dim * Elt.Reg.Dim_Increment * 8);

         when Cluster_Element =>
            Ret := Ret + Get_Size (Elt.Cluster.all);
      end case;

      if (Ret + 1) mod 32 /= 0 then
         Ret := Ret + 32 - (Ret mod 32);
      end if;

      return Positive (Ret);
   end Get_Size;

   --------------------
   -- Insert_Element --
   --------------------

   procedure Insert_Element
     (Cluster : in out Cluster_T;
      Elt     : Peripheral_Element)
   is
      Added  : Boolean;
      Offset : constant Natural := Address_Offset (Elt);
   begin
      if Cluster.Content.Contains (Elt) then
         return;
      end if;

      Added := False;

      for J in 1 ..
        Integer (Peripheral_Element_Vectors.Length (Cluster.Content))
      loop
         case Cluster.Content (J).Kind is
            when Register_Element =>
               if Cluster.Content (J).Reg.Address_Offset > Offset then
                  Cluster.Content.Insert (J, Elt);
                  Added := True;
                  exit;
               end if;
            when Cluster_Element =>
               if Cluster.Content (J).Cluster.Address_Offset > Offset then
                  Cluster.Content.Insert (J, Elt);
                  Added := True;
                  exit;
               end if;
         end case;
      end loop;

      if not Added then
         Cluster.Content.Append (Elt);
      end if;
   end Insert_Element;

   --------------------------------
   -- Find_Overlapping_Registers --
   --------------------------------

   function Find_Overlapping_Registers
     (Reg_Set : Peripheral_Element_Vectors.Vector) return Boolean
   is
      use Unbounded;
      Ret      : Boolean := False;
      Idx      : Positive;
      Off      : Natural;
      Last     : Natural;
      Enum_Idx : Natural;

      function Image (N : Natural) return String;

      -----------
      -- Image --
      -----------

      function Image (N : Natural) return String
      is
         S : constant String := N'Img;
      begin
         return S (S'First + 1 .. S'Last);
      end Image;

   begin
      For J in Reg_Set.First_Index .. Reg_Set.Last_Index - 1 loop
         declare
            Elt  : Peripheral_Element renames Reg_Set (J);
            Off1 : constant Natural := Address_Offset (Elt);
         begin
            for K in J + 1 .. Reg_Set.Last_Index loop
               declare
                  Elt2 : Peripheral_Element renames Reg_Set (K);
               begin
                  exit when Off1 /= Address_Offset (Elt2);

                  if Reg_Set (J).Kind /= Reg_Set (K).Kind then
                     raise Constraint_Error with
                       "Registers and clusters overlapping is " &
                       "not supported for now";
                  end if;

                  case Reg_Set (J).Kind is
                     when Register_Element =>
                        Reg_Set (J).Reg.Is_Overlapping := True;
                        Reg_Set (K).Reg.Is_Overlapping := True;
                        Ret := True;
                     when Cluster_Element =>
                        Reg_Set (J).Cluster.Is_Overlapping := True;
                        Reg_Set (K).Cluster.Is_Overlapping := True;
                        Ret := True;
                  end case;
               end;
            end loop;
         end;
      end loop;

      if not Ret then
         return Ret;
      end if;


      Idx := Reg_Set.First_Index;
      while Idx < Reg_Set.Last_Index loop
         --  Do not perform a second pass if the register has already been
         --  detected as aliased
         if Is_Overlapping (Reg_Set (Idx)) then
            declare
               Elt    : constant Peripheral_Element := Reg_Set (Idx);
               Prefix : constant String := To_String (Name (Elt));

            begin
               Last := Prefix'Last;
               Off  := Address_Offset (Elt);
               --  First loop: look at another register at the same offset
               --  If found, mark the current register as overlapping, and find
               --  a prefix common to all overlapping registers.
               for K in Idx + 1 .. Reg_Set.Last_Index loop
                  exit when Address_Offset (Reg_Set (K)) /= Off;

                  for J in 1 .. Last loop
                     if J > Length (Name (Reg_Set (K)))
                       or else Prefix (J) /= Element (Name (Reg_Set (K)), J)
                     then
                        if Last /= 0 then
                           Last := J - 1;
                        end if;

                        exit;
                     end if;
                  end loop;
               end loop;
            end;

            --  Second loop: find enum values for the registers

            if Last = 0 then
               Enum_Idx := 1;
            end if;

            loop
               exit when Idx > Reg_Set.Last_Index;
               exit when Address_Offset (Reg_Set (Idx)) /= Off;

               declare
                  Elt    : constant Peripheral_Element := Reg_Set (Idx);
                  Prefix : constant String := To_String (Name (Elt));
               begin
                  if Last = 0 then
                     --  No common name found: let's imagine one
                     case Elt.Kind is
                        when Register_Element =>
                           Elt.Reg.Overlap_Suffix :=
                             To_Unbounded_String ("Mode_" & Image (Enum_Idx));
                        when Cluster_Element =>
                           Elt.Cluster.Overlap_Suffix :=
                             To_Unbounded_String ("Mode_" & Image (Enum_Idx));
                     end case;

                     Enum_Idx := Enum_Idx + 1;

                  elsif Last = Prefix'Last then
                     case Elt.Kind is
                        when Register_Element =>
                           Elt.Reg.Overlap_Suffix :=
                             To_Unbounded_String ("Default");
                        when Cluster_Element =>
                           Elt.Cluster.Overlap_Suffix :=
                             To_Unbounded_String ("Default");
                     end case;

                  else
                     --  If we have names like "CMR0",
                     --  "CMR0_WAVE_EQ_1", the suffix for the second must
                     --  skip the '_'.
                     declare
                        Skip : Positive := Last + 1;
                     begin
                        while Prefix (Skip) = '_' loop
                           Skip := Skip + 1;
                        end loop;

                     case Elt.Kind is
                        when Register_Element =>
                           Elt.Reg.Overlap_Suffix :=
                             To_Unbounded_String
                               (Prefix (Skip .. Prefix'Last));
                        when Cluster_Element =>
                           Elt.Cluster.Overlap_Suffix :=
                             To_Unbounded_String
                               (Prefix (Skip .. Prefix'Last));
                     end case;
                     end;
                  end if;

                  Idx := Idx + 1;
               end;
            end loop;
         else
            Idx := Idx + 1;
         end if;
      end loop;

      return Ret;
   end Find_Overlapping_Registers;

   -----------------------
   -- Find_Common_Types --
   -----------------------

   procedure Find_Common_Types (Elts : Peripheral_Element_Vectors.Vector)
   is
   begin
      --  Look for fields with similar types, to use a single type definition
      --  in such situation
      for J in Elts.First_Index .. Elts.Last_Index - 1 loop
         if Elts (J).Kind = Register_Element
           and then Elts (J).Reg.Type_Holder = null
         then
            for K in J + 1 .. Elts.Last_Index loop
               if Elts (K).Kind = Register_Element then
                  if Equal (Elts (J).Reg, Elts (K).Reg) then
                     --  Simple case: two identical registers.
                     Elts (K).Reg.Type_Holder := Elts (J).Reg;

                  else
                     declare
                        Prefix : constant Unbounded.Unbounded_String :=
                                   Similar_Type (Elts (J).Reg, Elts (K).Reg);
                     begin
                        if Unbounded.Length (Prefix) > 0 then
                           --  We have similar types, but with different names.
                           --  In such situation, it'd be nice to generate a
                           --  common type definition.
                           Elts (J).Reg.Type_Name := Prefix;
                           Elts (K).Reg.Type_Holder := Elts (J).Reg;
                        end if;
                     end;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
   end Find_Common_Types;

   ---------------------------
   -- Get_Discriminent_Type --
   ---------------------------

   function Get_Discriminent_Type
     (Reg_Set   : Peripheral_Element_Vectors.Vector;
      Spec      : in out Ada_Gen.Ada_Spec;
      Type_Name : String) return Ada_Type_Enum
   is
      use Unbounded;
      Ret    : Ada_Type_Enum :=
                 New_Type_Enum (Id => Type_Name & "_Disc");
      Values : String_List.Vector;
      Val    : Ada_Enum_Value;

   begin
      for Reg of Reg_Set loop
         if Is_Overlapping (Reg)
           and then not Values.Contains (To_String (Overlap_Suffix (Reg)))
         then
            Values.Append (To_String (Overlap_Suffix (Reg)));
         end if;
      end loop;

      for S of Values loop
         Val := Add_Enum_Id (Spec, Ret, S);

         declare
            Actual : constant String := To_String (Id (Val));
         begin
            if Actual /= S then
               for Reg of Reg_Set loop
                  if Is_Overlapping (Reg)
                    and then To_String (Overlap_Suffix (Reg)) = S
                  then
                     case Reg.Kind is
                        when Register_Element =>
                           Reg.Reg.Overlap_Suffix := Id (Val);
                        when Cluster_Element =>
                           Reg.Cluster.Overlap_Suffix := Id (Val);
                     end case;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      return Ret;
   end Get_Discriminent_Type;

   -----------------------
   -- Dump_Cluster_Type --
   -----------------------

   procedure Dump_Cluster_Type
     (Spec      : in out Ada_Gen.Ada_Spec;
      Cluster   : in out Cluster_T;
      Type_Name : String)
   is
      use Ada.Strings.Unbounded;

      function Create_Record return Ada_Type_Record'Class;

      -------------------
      -- Create_Record --
      -------------------

      function Create_Record return Ada_Type_Record'Class
      is
      begin
         if Find_Overlapping_Registers (Cluster.Content) then
            declare
               Enum : Ada_Type_Enum :=
                        Get_Discriminent_Type (Cluster.Content,
                                               Spec,
                                               To_String (Cluster.Type_Name));
            begin
               Add (Spec, Enum);
               return New_Type_Union
                 (Type_Name,
                  "Discriminent",
                  Enum,
                  To_String (Cluster.Description));
            end;
         else
            --  No overlapping register: generate a simple record
            return New_Type_Record
              (Type_Name,
               To_String (Cluster.Description));
         end if;
      end Create_Record;

      Rec : Ada_Type_Record'Class := Create_Record;

   begin
      Add_Aspect (Rec, "Volatile");
      Add_Size_Aspect (Rec, Get_Size (Cluster));

      for Elt of Cluster.Content loop
         if Elt.Kind = Register_Element and then Elt.Reg.Is_Overlapping then
            Add_Field
              (Ada_Type_Union (Rec),
               Enum_Val => To_String (Elt.Reg.Overlap_Suffix),
               Id       => To_String (Elt.Reg.Name),
               Typ      => Get_Ada_Type (Elt.Reg),
               Offset   => Elt.Reg.Address_Offset,
               LSB      => 0,
               MSB      => (if Elt.Reg.Dim = 1
                            then Elt.Reg.Reg_Properties.Size - 1
                            else Elt.Reg.Dim * Elt.Reg.Dim_Increment * 8 - 1),
               Comment  => To_String (Elt.Reg.Description));

         else
            case Elt.Kind is
               when Register_Element =>
                  Add_Field
                    (Rec,
                     Id      => To_String (Elt.Reg.Name),
                     Typ     => Get_Ada_Type (Elt.Reg),
                     Offset  => Elt.Reg.Address_Offset,
                     LSB     => 0,
                     MSB     => (if Elt.Reg.Dim = 1
                                 then Elt.Reg.Reg_Properties.Size - 1
                                 else Elt.Reg.Dim * Elt.Reg.Dim_Increment * 8 - 1),
                     Comment => To_String (Elt.Reg.Description));
               when Cluster_Element =>
                  Add_Field
                    (Rec,
                     Id      => To_String (Elt.Cluster.Name),
                     Typ     => Type_Holders.Element (Elt.Cluster.Ada_Type),
                     Offset  => Elt.Cluster.Address_Offset,
                     LSB     => 0,
                     MSB     => (if Elt.Cluster.Dim = 1
                                 then Elt.Cluster.Reg_Properties.Size - 1
                                 else Elt.Cluster.Dim * Elt.Cluster.Dim_Increment * 8 - 1),
                     Comment => To_String (Elt.Cluster.Description));
            end case;
         end if;
      end loop;

      Add (Spec, Rec);
      Cluster.Ada_Type := Type_Holders.To_Holder (Rec);
   end Dump_Cluster_Type;

   ----------
   -- Dump --
   ----------

   procedure Dump
     (Spec    : in out Ada_Gen.Ada_Spec;
      Cluster : Cluster_Access)
   is
      use Ada.Strings.Unbounded;

   begin
      if not Cluster.Content.Is_Empty then
         Add (Spec, New_Comment_Box ("Cluster's Registers"));
      end if;

      Find_Common_Types (Cluster.Content);

      for Elt of Cluster.Content loop
         case Elt.Kind is
            when Register_Element =>
               Dump (Spec, Elt.Reg);
            when Cluster_Element =>
               Dump (Spec, Elt.Cluster);
         end case;
      end loop;

      Dump_Cluster_Type
        (Spec, Cluster.all, To_String (Cluster.Type_Name) & "_Cluster");

      if Cluster.Dim > 1 then
         declare
            Array_T : Ada_Type_Array;
         begin
            Array_T :=
              New_Type_Array
                (Id           => To_String (Cluster.Type_Name) & "_Clusters",
                 Index_Type   => "",
                 Index_First  => 0,
                 Index_Last   => Cluster.Dim - 1,
                 Element_Type => -Cluster.Ada_Type,
                 Comment      => To_String (Cluster.Description));
            Add (Spec, Array_T);
            Cluster.Ada_Type := -Array_T;
         end;
      end if;
   end Dump;

end Descriptors.Cluster;